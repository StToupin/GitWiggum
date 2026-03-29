module Application.Job.DiffAiResponseJob where

import qualified Control.Exception as Exception
import qualified Data.Text as Text
import qualified System.Environment as Environment
import IHP.ControllerPrelude (fetchOne, query)
import IHP.Job.Types
import IHP.OpenAI
import IHP.Prelude
import IHP.QueryBuilder (filterWhere)
import qualified Application.Service.DiffAI as DiffAI
import Generated.Types

instance Job DiffAiResponseJob where
    perform diffAiResponseJob = do
        promptResult <- DiffAI.fetchDiffAiPrompt diffAiResponseJob

        prompt <-
            case promptResult of
                Left errorMessage ->
                    Exception.throwIO (userError (cs errorMessage))
                Right promptText ->
                    pure promptText

        openAiApiKey <- requireOpenAiApiKey
        responseRef <- newIORef ""

        _ <-
            streamCompletion
                (defaultConfig openAiApiKey)
                (buildCompletionRequest prompt)
                (markJobStreamStarted diffAiResponseJob)
                (appendChunkToJob diffAiResponseJob responseRef)

        finalResponse <- readIORef responseRef

        when (Text.null (Text.strip finalResponse)) do
            Exception.throwIO (userError (cs ("Diff AI response stream finished without content" :: Text)))

        persistJobResponse diffAiResponseJob finalResponse

    maxAttempts = 2
    timeoutInMicroseconds = Just (60 * 1000000)

buildCompletionRequest :: Text -> CompletionRequest
buildCompletionRequest prompt =
    newCompletionRequest
        { model = "gpt-4o-mini"
        , temperature = Just 0.1
        , messages =
            [ systemMessage "You explain pull request diffs for code reviewers. Stay concrete, concise, and grounded in the provided diff."
            , userMessage prompt
            ]
        }

markJobStreamStarted :: (?modelContext :: ModelContext) => DiffAiResponseJob -> IO ()
markJobStreamStarted diffAiResponseJob = do
    _ <-
        diffAiResponseJob
            |> set #response (Just "")
            |> set #dismissed False
            |> set #lastError Nothing
            |> updateRecord
    pure ()

appendChunkToJob :: (?modelContext :: ModelContext) => DiffAiResponseJob -> IORef Text -> CompletionChunk -> IO ()
appendChunkToJob diffAiResponseJob responseRef completionChunk = do
    let chunkText = extractChunkText completionChunk

    unless (Text.null chunkText) do
        modifyIORef' responseRef (<> chunkText)
        accumulatedResponse <- readIORef responseRef
        persistJobResponse diffAiResponseJob accumulatedResponse

persistJobResponse :: (?modelContext :: ModelContext) => DiffAiResponseJob -> Text -> IO ()
persistJobResponse diffAiResponseJob responseText = do
    currentJob <-
        query @DiffAiResponseJob
            |> filterWhere (#id, get #id diffAiResponseJob)
            |> fetchOne

    _ <-
        currentJob
            |> set #response (Just responseText)
            |> set #dismissed False
            |> set #lastError Nothing
            |> updateRecord
    pure ()

extractChunkText :: CompletionChunk -> Text
extractChunkText CompletionChunk { choices } =
    choices
        |> mapMaybe extractChunkChoiceText
        |> Text.concat

extractChunkChoiceText :: CompletionChunkChoice -> Maybe Text
extractChunkChoiceText CompletionChunkChoice { delta = Delta { content } } = content

requireOpenAiApiKey :: IO Text
requireOpenAiApiKey = do
    maybeOpenAiApiKey <- Environment.lookupEnv "OPENAI_API_KEY"

    case maybeOpenAiApiKey of
        Just openAiApiKey ->
            pure (cs openAiApiKey)
        Nothing ->
            Exception.throwIO (userError (cs ("OPENAI_API_KEY is not set" :: Text)))
