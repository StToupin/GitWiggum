module Application.PromptMetadata (
    PromptMetadata (..),
    parsePromptMetadata,
) where

import Application.Base64 (decodeBase64Bytes)
import qualified Data.Aeson as Aeson
import Data.Char (isSpace)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import qualified Data.Text.Encoding.Error as Text.Encoding.Error
import GHC.Generics (Generic)
import IHP.Prelude

data PromptMetadata = PromptMetadata
    { source :: Text
    , prompt :: Text
    , thinking :: Maybe Text
    , threadId :: Maybe Text
    , sessionFile :: Maybe Text
    }
    deriving (Eq, Show)

data CaptureTrailer = CaptureTrailer
    { captureSource :: Text
    , capturePrompt :: Text
    , capturePromptMessages :: [CapturePromptMessage]
    , captureThinking :: Maybe CaptureThinking
    , captureThreadId :: Maybe Text
    , captureSessionFile :: Maybe Text
    }
    deriving (Eq, Show, Generic)

instance Aeson.FromJSON CaptureTrailer where
    parseJSON = Aeson.withObject "CaptureTrailer" \object ->
        CaptureTrailer
            <$> object Aeson..: "source"
            <*> object Aeson..: "prompt"
            <*> object Aeson..:? "promptMessages" Aeson..!= []
            <*> object Aeson..:? "thinking"
            <*> object Aeson..:? "threadId"
            <*> object Aeson..:? "sessionFile"

data CapturePromptMessage = CapturePromptMessage
    { text :: Maybe Text
    }
    deriving (Eq, Show, Generic)

instance Aeson.FromJSON CapturePromptMessage where
    parseJSON = Aeson.withObject "CapturePromptMessage" \object ->
        CapturePromptMessage
            <$> object Aeson..:? "text"

data CaptureThinking = CaptureThinking
    { summary :: [CaptureThinkingSummary]
    , encryptedContent :: Maybe Text
    }
    deriving (Eq, Show, Generic)

instance Aeson.FromJSON CaptureThinking where
    parseJSON = Aeson.withObject "CaptureThinking" \object ->
        CaptureThinking
            <$> object Aeson..:? "summary" Aeson..!= []
            <*> object Aeson..:? "encrypted_content"

data CaptureThinkingSummary = CaptureThinkingSummary
    { text :: Maybe Text
    }
    deriving (Eq, Show, Generic)

instance Aeson.FromJSON CaptureThinkingSummary where
    parseJSON = Aeson.withObject "CaptureThinkingSummary" \object ->
        CaptureThinkingSummary
            <$> object Aeson..:? "text"

parsePromptMetadata :: Text -> Maybe PromptMetadata
parsePromptMetadata commitMessage = do
    encodedCapture <- extractCaptureTrailer commitMessage
    decodedPayload <- either (const Nothing) Just (decodePromptText encodedCapture)
    captureTrailer <- either (const Nothing) Just (Aeson.eitherDecodeStrict' (Text.Encoding.encodeUtf8 decodedPayload))
    pure
        PromptMetadata
            { source = captureSource captureTrailer
            , prompt = renderPromptText captureTrailer
            , thinking = captureThinking captureTrailer >>= renderThinkingSummary
            , threadId = captureThreadId captureTrailer
            , sessionFile = captureSessionFile captureTrailer
            }

extractCaptureTrailer :: Text -> Maybe Text
extractCaptureTrailer commitMessage =
    extractTrailer "GitWiggum-Capture-Base64" commitMessage
        <|> extractTrailer "Codex-Context" commitMessage

decodePromptText :: Text -> Either Text Text
decodePromptText encodedPrompt = do
    decodedBytes <- decodeBase64Bytes (Text.unpack (Text.filter (not . isSpace) encodedPrompt))
    pure (Text.Encoding.decodeUtf8With Text.Encoding.Error.strictDecode decodedBytes)

extractTrailer :: Text -> Text -> Maybe Text
extractTrailer trailerName commitMessage =
    commitMessage
        |> Text.lines
        |> reverse
        |> mapMaybe (\line -> Text.stripPrefix (trailerName <> ": ") line)
        |> listToMaybe

renderThinkingSummary :: CaptureThinking -> Maybe Text
renderThinkingSummary CaptureThinking{summary} =
    let renderedSummary =
            summary
                |> mapMaybe (\CaptureThinkingSummary{text} -> text)
                |> map Text.strip
                |> filter (not . Text.null)
                |> Text.intercalate "\n"
                |> Text.strip
     in if Text.null renderedSummary then Nothing else Just renderedSummary

renderPromptText :: CaptureTrailer -> Text
renderPromptText captureTrailer =
    let promptMessages =
            capturePromptMessages captureTrailer
                |> mapMaybe (\CapturePromptMessage{text} -> text)
                |> map stripEnvironmentContext
                |> map Text.strip
                |> filter (not . Text.null)
        fallbackPrompt =
            capturePrompt captureTrailer
                |> stripEnvironmentContext
                |> Text.strip
     in if null promptMessages
            then fallbackPrompt
            else Text.intercalate "\n" promptMessages

stripEnvironmentContext :: Text -> Text
stripEnvironmentContext promptText =
    case Text.breakOn "<environment_context>" promptText of
        (beforeContext, afterContext)
            | Text.null afterContext -> promptText
            | otherwise ->
                let remainingText =
                        case Text.breakOn "</environment_context>" afterContext of
                            (_, closingTagAndRest)
                                | Text.null closingTagAndRest -> ""
                                | otherwise -> Text.drop (Text.length "</environment_context>") closingTagAndRest
                 in (beforeContext <> remainingText)
                        |> stripEnvironmentContext
