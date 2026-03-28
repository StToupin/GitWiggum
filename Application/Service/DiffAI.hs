module Application.Service.DiffAI
    ( DiffAiLocation (..)
    , diffAiSideNew
    , diffAiSideOld
    , buildDiffAiFingerprint
    , enqueueOrReuseDiffAiResponseJob
    , fetchDiffAiPrompt
    ) where

import qualified Data.Text as Text
import IHP.ControllerPrelude (fetchOneOrNothing, query)
import IHP.Job.Types (JobStatus (..))
import IHP.ModelSupport (InputValue (inputValue), createRecord, newRecord, updateRecord)
import IHP.Prelude
import IHP.QueryBuilder (filterWhere)
import qualified Application.Service.GitRepository as GitRepository
import Generated.Types

data DiffAiLocation = DiffAiLocation
    { filePath :: Text
    , side :: Text
    , lineNumber :: Int
    }
    deriving (Eq, Show)

diffAiSideOld :: Text
diffAiSideOld = "old"

diffAiSideNew :: Text
diffAiSideNew = "new"

buildDiffAiFingerprint :: PullRequest -> Text -> DiffAiLocation -> Text
buildDiffAiFingerprint pullRequest headSha DiffAiLocation { filePath, side, lineNumber } =
    Text.intercalate
        ":"
        [ inputValue (get #id pullRequest)
        , headSha
        , filePath
        , side
        , tshow lineNumber
        ]

enqueueOrReuseDiffAiResponseJob ::
    (?modelContext :: ModelContext) =>
    PullRequest ->
    Text ->
    DiffAiLocation ->
    IO DiffAiResponseJob
enqueueOrReuseDiffAiResponseJob pullRequest headSha location = do
    now <- getCurrentTime
    let fingerprint = buildDiffAiFingerprint pullRequest headSha location
    existingJob <-
        query @DiffAiResponseJob
            |> filterWhere (#fingerprint, fingerprint)
            |> fetchOneOrNothing

    case existingJob of
        Just diffAiResponseJob ->
            refreshExistingJob now diffAiResponseJob
        Nothing ->
            newRecord @DiffAiResponseJob
                |> set #pullRequestId (get #id pullRequest)
                |> set #filePath location.filePath
                |> set #side location.side
                |> set #lineNumber location.lineNumber
                |> set #headSha headSha
                |> set #fingerprint fingerprint
                |> set #response Nothing
                |> set #dismissed False
                |> set #status JobStatusNotStarted
                |> set #runAt now
                |> createRecord
  where
    refreshExistingJob now diffAiResponseJob =
        case get #status diffAiResponseJob of
            JobStatusFailed ->
                resetJob now diffAiResponseJob
            JobStatusTimedOut ->
                resetJob now diffAiResponseJob
            _ ->
                diffAiResponseJob
                    |> set #dismissed False
                    |> updateRecord

    resetJob now diffAiResponseJob =
        diffAiResponseJob
            |> set #response Nothing
            |> set #dismissed False
            |> set #status JobStatusNotStarted
            |> set #lockedBy Nothing
            |> set #lockedAt Nothing
            |> set #runAt now
            |> set #attemptsCount 0
            |> set #lastError Nothing
            |> updateRecord

fetchDiffAiPrompt ::
    (?modelContext :: ModelContext) =>
    DiffAiResponseJob ->
    IO (Either Text Text)
fetchDiffAiPrompt diffAiResponseJob = do
    pullRequest <-
        query @PullRequest
            |> filterWhere (#id, get #pullRequestId diffAiResponseJob)
            |> fetchOneOrNothing

    case pullRequest of
        Nothing ->
            pure (Left "Pull request not found for diff AI job")
        Just pullRequestRecord -> do
            repository <-
                query @Repository
                    |> filterWhere (#id, get #repositoryId pullRequestRecord)
                    |> fetchOneOrNothing

            case repository of
                Nothing ->
                    pure (Left "Repository not found for diff AI job")
                Just repositoryRecord -> do
                    owner <-
                        query @User
                            |> filterWhere (#id, get #ownerUserId repositoryRecord)
                            |> fetchOneOrNothing

                    case owner of
                        Nothing ->
                            pure (Left "Repository owner not found for diff AI job")
                        Just ownerRecord -> do
                            commits <-
                                GitRepository.listPullRequestCommits
                                    ownerRecord
                                    repositoryRecord
                                    (get #baseBranch pullRequestRecord)
                                    (get #headSha diffAiResponseJob)

                            rawDiff <-
                                GitRepository.readPullRequestRawDiff
                                    ownerRecord
                                    repositoryRecord
                                    (get #baseBranch pullRequestRecord)
                                    (get #headSha diffAiResponseJob)

                            pure $
                                Right
                                    (buildPromptText
                                        pullRequestRecord
                                        diffAiResponseJob
                                        commits
                                        (fromMaybe "" rawDiff)
                                    )

buildPromptText :: PullRequest -> DiffAiResponseJob -> [GitRepository.GitPullRequestCommit] -> Text -> Text
buildPromptText pullRequest diffAiResponseJob commits rawDiff =
    Text.unlines
        [ "Explain the selected pull request diff location for a reviewer."
        , "Focus on what changed, why it matters, and any risk you can see from the available context."
        , "Keep the answer concise and grounded in the diff."
        , ""
        , "Pull request title:"
        , get #title pullRequest
        , ""
        , "Pull request description:"
        , fromMaybe "" (get #description pullRequest)
        , ""
        , "Base branch:"
        , get #baseBranch pullRequest
        , ""
        , "Compare head SHA:"
        , get #headSha diffAiResponseJob
        , ""
        , "Selected diff location:"
        , Text.intercalate
            " "
            [ get #filePath diffAiResponseJob
            , "(" <> get #side diffAiResponseJob <> " line " <> tshow (get #lineNumber diffAiResponseJob) <> ")"
            ]
        , ""
        , "Commit names in this pull request:"
        , renderCommitNames commits
        , ""
        , "Full pull request diff:"
        , rawDiff
        ]

renderCommitNames :: [GitRepository.GitPullRequestCommit] -> Text
renderCommitNames [] = "(no commits found)"
renderCommitNames commits =
    commits
        |> map (\commit -> "- " <> GitRepository.commitSubject commit)
        |> Text.unlines
