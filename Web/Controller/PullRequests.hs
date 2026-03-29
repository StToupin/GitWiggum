module Web.Controller.PullRequests where

import qualified Application.Service.DiffAI as DiffAI
import qualified Data.List as List
import qualified Network.HTTP.Types as HTTP
import qualified Network.Wai as WAI
import qualified Data.Text as Text
import IHP.ModelSupport (trackTableRead)
import IHP.ValidationSupport.Types (attachFailure, getValidationFailure)
import IHP.ValidationSupport.ValidateField (nonEmpty, validateField)
import Application.Service.GitRepository (listRepositoryBranches)
import qualified Application.Service.GitRepository as GitRepository
import Web.Controller.Prelude
import Web.View.PullRequests.Commits
import Web.View.PullRequests.Conversation
import Web.View.PullRequests.Files
import Web.View.PullRequests.New

instance Controller PullRequestsController where
    beforeAction = ensureIsUser

    action NewPullRequestAction { ownerSlug, repositoryName } = do
        (owner, repository) <- fetchRepositoryContext ownerSlug repositoryName
        availableBranches <- liftIO $ listRepositoryBranches owner repository
        let pullRequest = buildInitialPullRequest currentUser repository availableBranches
        render NewView { owner, repository, pullRequest, availableBranches }

    action CreatePullRequestAction { ownerSlug, repositoryName } = do
        (owner, repository) <- fetchRepositoryContext ownerSlug repositoryName
        availableBranches <- liftIO $ listRepositoryBranches owner repository
        nextNumber <- nextPullRequestNumber repository
        let isDraftParam = paramOrDefault ("" :: Text) "isDraft"
        let pullRequest =
                buildPullRequest
                    currentUser
                    repository
                    nextNumber
                    (paramOrDefault "" "title")
                    (paramOrDefault "" "description")
                    (paramOrDefault (get #defaultBranch repository) "baseBranch")
                    (paramOrDefault "" "compareBranch")
                    (isDraftParam == ("on" :: Text))
        let pullRequestWithValidation =
                pullRequest
                    |> validateField #title nonEmpty
                    |> validateField #baseBranch nonEmpty
                    |> validateField #compareBranch nonEmpty
                    |> validatePullRequestBranches availableBranches

        if hasPullRequestErrors pullRequestWithValidation
            then render NewView { owner, repository, pullRequest = pullRequestWithValidation, availableBranches }
            else do
                createdPullRequest <- pullRequestWithValidation |> createRecord
                setSuccessMessage "Pull request created."
                redirectTo
                    ShowPullRequestConversationAction
                        { ownerSlug
                        , repositoryName
                        , pullRequestNumber = get #number createdPullRequest
                        }

    action ShowPullRequestConversationAction { ownerSlug, repositoryName, pullRequestNumber } = do
        (owner, repository, pullRequest, author) <- fetchPullRequestContext ownerSlug repositoryName pullRequestNumber
        render ConversationView { owner, repository, pullRequest, author }

    action ShowPullRequestCommitsAction { ownerSlug, repositoryName, pullRequestNumber } = do
        (owner, repository, pullRequest, author) <- fetchPullRequestContext ownerSlug repositoryName pullRequestNumber
        commits <-
            liftIO $
                GitRepository.listPullRequestCommits
                    owner
                    repository
                    (get #baseBranch pullRequest)
                    (get #compareBranch pullRequest)
        render CommitsView { owner, repository, pullRequest, author, commits }

    action ShowPullRequestFilesAction { ownerSlug, repositoryName, pullRequestNumber } = do
        autoRefresh do
            (owner, repository, pullRequest, author) <- fetchPullRequestContext ownerSlug repositoryName pullRequestNumber
            headSha <- liftIO $ GitRepository.readPullRequestHeadSha owner repository (get #compareBranch pullRequest)
            diffFiles <-
                liftIO $
                    GitRepository.readPullRequestDiff
                        owner
                        repository
                        (get #baseBranch pullRequest)
                        (get #compareBranch pullRequest)
            trackTableRead "diff_ai_response_jobs"
            diffAiJobs <-
                query @DiffAiResponseJob
                    |> filterWhere (#pullRequestId, get #id pullRequest)
                    |> filterWhere (#dismissed, False)
                    |> fetch
            render FilesView { owner, repository, pullRequest, author, diffFiles, diffAiJobs, headSha }

    action CreatePullRequestDiffAiJobAction { ownerSlug, repositoryName, pullRequestNumber } = do
        (owner, repository, pullRequest, _author) <- fetchPullRequestContext ownerSlug repositoryName pullRequestNumber

        let maybeFilePath = paramOrNothing @Text "filePath"
        let maybeSide = paramOrNothing @Text "side"
        let maybeLineNumber = paramOrNothing @Int "lineNumber"

        case (maybeFilePath, maybeSide, maybeLineNumber) of
            (Just filePath, Just side, Just lineNumber)
                | side `elem` [DiffAI.diffAiSideOld, DiffAI.diffAiSideNew] -> do
                    maybeHeadSha <- liftIO $ GitRepository.readPullRequestHeadSha owner repository (get #compareBranch pullRequest)

                    case maybeHeadSha of
                        Just headSha -> do
                            let location = DiffAI.DiffAiLocation { filePath, side, lineNumber }
                            diffAiResponseJob <- DiffAI.enqueueOrReuseDiffAiResponseJob pullRequest headSha location
                            renderFragment
                                DiffAiResponseRowView
                                    { ownerSlug
                                    , repositoryName
                                    , pullRequestNumber
                                    , diffAiResponseJob
                                    }
                        Nothing ->
                            respondAndExitWithHeaders (WAI.responseLBS HTTP.status422 [] "Could not resolve pull request head SHA")
            _ ->
                respondAndExitWithHeaders (WAI.responseLBS HTTP.status422 [] "Missing diff AI location")

    action ShowPullRequestDiffAiJobAction { ownerSlug, repositoryName, pullRequestNumber, diffAiResponseJobId } = do
        (_owner, _repository, pullRequest, _author) <- fetchPullRequestContext ownerSlug repositoryName pullRequestNumber
        diffAiResponseJob <-
            query @DiffAiResponseJob
                |> filterWhere (#id, diffAiResponseJobId)
                |> filterWhere (#pullRequestId, get #id pullRequest)
                |> fetchOne
        renderFragment
            DiffAiResponseRowView
                { ownerSlug
                , repositoryName
                , pullRequestNumber
                , diffAiResponseJob
                }

buildInitialPullRequest :: User -> Repository -> [Text] -> PullRequest
buildInitialPullRequest currentUser repository availableBranches =
    buildPullRequest
        currentUser
        repository
        0
        ""
        ""
        (get #defaultBranch repository)
        (defaultCompareBranch availableBranches (get #defaultBranch repository))
        False

buildPullRequest :: User -> Repository -> Int -> Text -> Text -> Text -> Text -> Bool -> PullRequest
buildPullRequest currentUser repository number title description baseBranch compareBranch isDraft =
    newRecord @PullRequest
        |> set #repositoryId (get #id repository)
        |> set #number number
        |> set #title (Text.strip title)
        |> set #description (normalizeDescription description)
        |> set #baseBranch (Text.strip baseBranch)
        |> set #compareBranch (Text.strip compareBranch)
        |> set #authorUserId (get #id currentUser)
        |> set #state "open"
        |> set #isDraft isDraft

normalizeDescription :: Text -> Maybe Text
normalizeDescription description =
    description
        |> Text.strip
        |> \value -> if Text.null value then Nothing else Just value

defaultCompareBranch :: [Text] -> Text -> Text
defaultCompareBranch availableBranches baseBranch =
    availableBranches
        |> List.find (/= baseBranch)
        |> fromMaybe ""

validatePullRequestBranches :: [Text] -> PullRequest -> PullRequest
validatePullRequestBranches availableBranches pullRequest =
    pullRequest
        |> attachIfInvalidBaseBranch
        |> attachIfInvalidCompareBranch
        |> attachIfSameBranch
  where
    attachIfInvalidBaseBranch record
        | Text.null (get #baseBranch record) = record
        | get #baseBranch record `elem` availableBranches = record
        | otherwise = record |> attachFailure #baseBranch "Choose a valid base branch"

    attachIfInvalidCompareBranch record
        | Text.null (get #compareBranch record) = record
        | get #compareBranch record `elem` availableBranches = record
        | otherwise = record |> attachFailure #compareBranch "Choose a valid compare branch"

    attachIfSameBranch record
        | not (Text.null (get #baseBranch record))
            && not (Text.null (get #compareBranch record))
            && get #baseBranch record == get #compareBranch record =
            record |> attachFailure #compareBranch "Choose a compare branch different from the base branch"
        | otherwise =
            record

hasPullRequestErrors :: PullRequest -> Bool
hasPullRequestErrors pullRequest =
    isJust (getValidationFailure #title pullRequest)
        || isJust (getValidationFailure #baseBranch pullRequest)
        || isJust (getValidationFailure #compareBranch pullRequest)

nextPullRequestNumber :: (?modelContext :: ModelContext) => Repository -> IO Int
nextPullRequestNumber repository = do
    latestPullRequest <-
        query @PullRequest
            |> filterWhere (#repositoryId, get #id repository)
            |> orderByDesc #number
            |> fetchOneOrNothing

    pure $
        case latestPullRequest of
            Just pullRequest -> get #number pullRequest + 1
            Nothing -> 1

fetchRepositoryContext ::
    (?modelContext :: ModelContext) =>
    Text ->
    Text ->
    IO (User, Repository)
fetchRepositoryContext ownerSlug repositoryName = do
    owner <-
        query @User
            |> filterWhere (#username, ownerSlug)
            |> fetchOne

    repository <-
        query @Repository
            |> filterWhere (#ownerUserId, get #id owner)
            |> filterWhere (#name, repositoryName)
            |> fetchOne

    pure (owner, repository)

fetchPullRequestContext ::
    (?modelContext :: ModelContext) =>
    Text ->
    Text ->
    Int ->
    IO (User, Repository, PullRequest, User)
fetchPullRequestContext ownerSlug repositoryName pullRequestNumber = do
    (owner, repository) <- fetchRepositoryContext ownerSlug repositoryName
    pullRequest <-
        query @PullRequest
            |> filterWhere (#repositoryId, get #id repository)
            |> filterWhere (#number, pullRequestNumber)
            |> fetchOne
    author <-
        query @User
            |> filterWhere (#id, get #authorUserId pullRequest)
            |> fetchOne

    pure (owner, repository, pullRequest, author)
