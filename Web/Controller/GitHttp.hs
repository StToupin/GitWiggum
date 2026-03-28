module Web.Controller.GitHttp where

import Application.Service.GitRepository
import qualified Network.HTTP.Types as HTTP
import qualified Network.HTTP.Types.Header as HTTPHeader
import qualified Network.Wai as WAI
import Web.Controller.Prelude

instance Controller GitHttpController where
    action RepositoryGitHttpAction { ownerSlug, repositoryName, gitPathInfo } = do
        repositoryContext <- fetchPublicRepositoryContext ownerSlug repositoryName

        case repositoryContext of
            Nothing ->
                respondAndExit gitHttpNotFoundResponse
            Just (owner, repository) -> do
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
                                , authType = Nothing
                                , remoteUser = Nothing
                                , requestBody
                                }

                case backendResult of
                    Left _ ->
                        respondAndExit gitHttpBackendFailureResponse
                    Right response ->
                        respondAndExit response

fetchPublicRepositoryContext ::
    (?modelContext :: ModelContext) =>
    Text ->
    Text ->
    IO (Maybe (User, Repository))
fetchPublicRepositoryContext ownerSlug repositoryName = do
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
                    |> filterWhere (#isPrivate, False)
                    |> fetchOneOrNothing

            pure $
                case repositoryOrNothing of
                    Nothing -> Nothing
                    Just repository -> Just (owner, repository)

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
