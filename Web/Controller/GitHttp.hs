module Web.Controller.GitHttp where

import Application.Service.GitHttpAuth
import Application.Service.GitRepository
import qualified Network.HTTP.Types as HTTP
import qualified Network.HTTP.Types.Header as HTTPHeader
import qualified Network.Wai as WAI
import Web.Controller.Prelude

instance Controller GitHttpController where
    action RepositoryGitHttpAction { ownerSlug, repositoryName, gitPathInfo } = do
        repositoryContext <- fetchRepositoryContext ownerSlug repositoryName

        case repositoryContext of
            Nothing ->
                respondAndExit gitHttpNotFoundResponse
            Just (owner, repository) -> do
                let accessLevel = gitHttpAccessLevel (cs request.rawQueryString) gitPathInfo
                authorizationResult <- authorizeRepositoryGitRequest repository accessLevel request

                case authorizationResult of
                    Left errorResponse ->
                        respondAndExit errorResponse
                    Right authenticatedRemoteUser -> do
                        when (accessLevel == GitWriteAccess) do
                            liftIO (enableHttpReceivePackOnDisk owner repository)

                        requestBody <- getRequestBody
                        backendResult <-
                            liftIO $
                                repositoryGitHttpResponse
                                    owner
                                    repository
                                    GitHttpRequest
                                        { gitPathInfo
                                        , queryString = cs request.rawQueryString
                                        , requestMethod = cs request.requestMethod
                                        , contentType = maybe "" cs (getHeader "Content-Type")
                                        , authType =
                                            case authenticatedRemoteUser of
                                                Just _ -> Just "Basic"
                                                Nothing -> Nothing
                                        , remoteUser = authenticatedRemoteUser
                                        , requestBody
                                        }

                        case backendResult of
                            Left _ ->
                                respondAndExit gitHttpBackendFailureResponse
                            Right response ->
                                respondAndExit response

fetchRepositoryContext ::
    (?modelContext :: ModelContext) =>
    Text ->
    Text ->
    IO (Maybe (User, Repository))
fetchRepositoryContext ownerSlug repositoryName = do
    ownerOrNothing <-
        query @User
            |> filterWhere (#username, ownerSlug)
            |> fetchOneOrNothing

    case ownerOrNothing of
        Nothing -> pure Nothing
        Just owner -> do
            repositoryOrNothing <-
                query @Repository
                    |> filterWhere (#ownerUserId, get #id owner)
                    |> filterWhere (#name, repositoryName)
                    |> fetchOneOrNothing

            pure $
                case repositoryOrNothing of
                    Nothing -> Nothing
                    Just repository -> Just (owner, repository)

authorizeRepositoryGitRequest ::
    (?modelContext :: ModelContext) =>
    Repository ->
    GitHttpAccessLevel ->
    WAI.Request ->
    IO (Either WAI.Response (Maybe Text))
authorizeRepositoryGitRequest repository accessLevel currentRequest
    | accessLevel == GitReadAccess && not (get #isPrivate repository) = pure (Right Nothing)
    | otherwise = do
        principalOrNothing <- authenticateGitHttpPrincipal currentRequest
        case principalOrNothing of
            Nothing ->
                pure (Left gitHttpUnauthorizedResponse)
            Just principal ->
                if canAccessRepository principal.user repository
                    then pure (Right (Just principal.remoteUser))
                    else pure (Left gitHttpForbiddenResponse)

canAccessRepository :: User -> Repository -> Bool
canAccessRepository user repository =
    get #id user == get #ownerUserId repository

gitHttpNotFoundResponse :: WAI.Response
gitHttpNotFoundResponse =
    WAI.responseLBS
        HTTP.status404
        [(HTTPHeader.hContentType, "text/plain; charset=utf-8")]
        "Repository not found.\n"

gitHttpBackendFailureResponse :: WAI.Response
gitHttpBackendFailureResponse =
    WAI.responseLBS
        HTTP.status500
        [(HTTPHeader.hContentType, "text/plain; charset=utf-8")]
        "Git backend failed.\n"

gitHttpUnauthorizedResponse :: WAI.Response
gitHttpUnauthorizedResponse =
    WAI.responseLBS
        HTTP.status401
        [ (HTTPHeader.hWWWAuthenticate, "Basic realm=\"GitWiggum\"")
        , (HTTPHeader.hContentType, "text/plain; charset=utf-8")
        ]
        "Authentication required.\n"

gitHttpForbiddenResponse :: WAI.Response
gitHttpForbiddenResponse =
    WAI.responseLBS
        HTTP.status403
        [(HTTPHeader.hContentType, "text/plain; charset=utf-8")]
        "You do not have access to this repository.\n"
