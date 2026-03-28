module Application.Service.GitHttpAuth
    ( GitHttpAccessLevel (..)
    , GitHttpPrincipal (..)
    , authenticateGitHttpPrincipal
    , gitHttpAccessLevel
    , parseBasicAuthorizationHeader
    ) where

import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Char8 as ByteString.Char8
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import qualified Data.Text.Encoding.Error as Text.Encoding.Error
import Data.Bits ((.&.), (.|.), shiftL, shiftR)
import Data.Char (ord)
import Data.Word (Word8)
import Generated.Types
import IHP.AuthSupport.Authentication (verifyPassword)
import IHP.ControllerPrelude (fetchOneOrNothing, query)
import IHP.Prelude
import IHP.QueryBuilder (filterWhereCaseInsensitive)
import qualified Network.HTTP.Types.Header as HTTPHeader
import qualified Network.Wai as WAI

data GitHttpAccessLevel
    = GitReadAccess
    | GitWriteAccess
    deriving (Eq, Show)

data GitHttpPrincipal = GitHttpPrincipal
    { user :: User
    , remoteUser :: Text
    }
    deriving (Eq, Show)

gitHttpAccessLevel :: Text -> Text -> GitHttpAccessLevel
gitHttpAccessLevel rawQueryString gitPathInfo =
    if "service=git-receive-pack" `Text.isInfixOf` rawQueryString || "/git-receive-pack" `Text.isSuffixOf` gitPathInfo
        then GitWriteAccess
        else GitReadAccess

parseBasicAuthorizationHeader :: Maybe ByteString.ByteString -> Maybe (Text, Text)
parseBasicAuthorizationHeader authorizationHeader = do
    rawValue <- authorizationHeader
    encodedCredentials <- ByteString.stripPrefix "Basic " rawValue
    decodedCredentials <- either (const Nothing) Just (decodeBase64Bytes (ByteString.Char8.unpack encodedCredentials))
    let credentialsText = Text.Encoding.decodeUtf8With Text.Encoding.Error.lenientDecode decodedCredentials
    let (loginName, passwordWithSeparator) = Text.breakOn ":" credentialsText
    password <- Text.stripPrefix ":" passwordWithSeparator
    let normalizedLoginName = Text.strip loginName
    if Text.null normalizedLoginName
        then Nothing
        else pure (normalizedLoginName, password)

authenticateGitHttpPrincipal ::
    (?modelContext :: ModelContext) =>
    WAI.Request ->
    IO (Maybe GitHttpPrincipal)
authenticateGitHttpPrincipal request =
    case parseBasicAuthorizationHeader (lookup HTTPHeader.hAuthorization request.requestHeaders) of
        Nothing ->
            pure Nothing
        Just (loginName, password) -> do
            maybeUser <- lookupUserByGitHttpLogin loginName
            pure $
                case maybeUser of
                    Just foundUser
                        | foundUser.isConfirmed && verifyPassword foundUser password ->
                            Just
                                GitHttpPrincipal
                                    { user = foundUser
                                    , remoteUser = preferredRemoteUser foundUser
                                    }
                    _ -> Nothing

lookupUserByGitHttpLogin :: (?modelContext :: ModelContext) => Text -> IO (Maybe User)
lookupUserByGitHttpLogin rawLoginName = do
    let loginName = Text.strip rawLoginName
    if Text.null loginName
        then pure Nothing
        else
            if "@" `Text.isInfixOf` loginName
                then lookupUserByEmail loginName
                else do
                    userByUsername <- lookupUserByUsername loginName
                    case userByUsername of
                        Just user -> pure (Just user)
                        Nothing -> lookupUserByEmail loginName

lookupUserByEmail :: (?modelContext :: ModelContext) => Text -> IO (Maybe User)
lookupUserByEmail emailAddress =
    query @User
        |> filterWhereCaseInsensitive (#email, emailAddress)
        |> fetchOneOrNothing

lookupUserByUsername :: (?modelContext :: ModelContext) => Text -> IO (Maybe User)
lookupUserByUsername username =
    query @User
        |> filterWhereCaseInsensitive (#username, username)
        |> fetchOneOrNothing

preferredRemoteUser :: User -> Text
preferredRemoteUser foundUser =
    case nonEmptyText foundUser.username of
        Just username -> username
        Nothing -> foundUser.email

nonEmptyText :: Text -> Maybe Text
nonEmptyText rawText =
    let strippedText = Text.strip rawText
     in if Text.null strippedText then Nothing else Just strippedText

decodeBase64Bytes :: String -> Either Text ByteString.ByteString
decodeBase64Bytes encodedBytes
    | length encodedBytes `mod` 4 /= 0 = Left "Invalid base64 length."
    | otherwise = ByteString.pack <$> go encodedBytes
  where
    go [] = Right []
    go (char1:char2:char3:char4:remainingChars) = do
        decodedChunk <- decodeChunk char1 char2 char3 char4
        (decodedChunk <>) <$> go remainingChars
    go _ =
        Left "Invalid base64 payload."

decodeChunk :: Char -> Char -> Char -> Char -> Either Text [Word8]
decodeChunk char1 char2 '=' '=' = do
    sextet1 <- decodeBase64Char char1
    sextet2 <- decodeBase64Char char2
    pure [fromIntegral ((sextet1 `shiftL` 2) .|. (sextet2 `shiftR` 4))]
decodeChunk char1 char2 char3 '=' = do
    sextet1 <- decodeBase64Char char1
    sextet2 <- decodeBase64Char char2
    sextet3 <- decodeBase64Char char3
    pure
        [ fromIntegral ((sextet1 `shiftL` 2) .|. (sextet2 `shiftR` 4))
        , fromIntegral (((sextet2 .&. 0x0F) `shiftL` 4) .|. (sextet3 `shiftR` 2))
        ]
decodeChunk char1 char2 char3 char4 = do
    sextet1 <- decodeBase64Char char1
    sextet2 <- decodeBase64Char char2
    sextet3 <- decodeBase64Char char3
    sextet4 <- decodeBase64Char char4
    pure
        [ fromIntegral ((sextet1 `shiftL` 2) .|. (sextet2 `shiftR` 4))
        , fromIntegral (((sextet2 .&. 0x0F) `shiftL` 4) .|. (sextet3 `shiftR` 2))
        , fromIntegral (((sextet3 .&. 0x03) `shiftL` 6) .|. sextet4)
        ]

decodeBase64Char :: Char -> Either Text Int
decodeBase64Char character
    | character >= 'A' && character <= 'Z' = Right (ord character - ord 'A')
    | character >= 'a' && character <= 'z' = Right (ord character - ord 'a' + 26)
    | character >= '0' && character <= '9' = Right (ord character - ord '0' + 52)
    | character == '+' = Right 62
    | character == '/' = Right 63
    | otherwise = Left "Invalid base64 payload."
