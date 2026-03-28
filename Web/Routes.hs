module Web.Routes where
import qualified Data.Text as Text
import IHP.RouterPrelude
import Generated.Types
import Web.Types

-- Generator Marker
instance AutoRoute StaticController
instance AutoRoute RegistrationsController
instance AutoRoute ConfirmationsController
instance AutoRoute SessionsController
instance AutoRoute PasswordResetsController
instance AutoRoute DashboardController

instance AutoRoute RepositoriesController where
    customRoutes =
        repositoryPullRequestsRoute
            <|> repositoryAgentsRoute
            <|> repositoryTreeRoute
            <|> showRepositoryRoute
      where
        repositoryPullRequestsRoute = do
            string "/"
            ownerSlug <- parseText
            string "/"
            repositoryName <- parseText
            string "/pull-requests"
            endOfInput
            onlyAllowMethods [GET, HEAD]
            pure RepositoryPullRequestsAction { ownerSlug, repositoryName }

        repositoryAgentsRoute = do
            string "/"
            ownerSlug <- parseText
            string "/"
            repositoryName <- parseText
            string "/agents"
            endOfInput
            onlyAllowMethods [GET, HEAD]
            pure RepositoryAgentsAction { ownerSlug, repositoryName }

        repositoryTreeRoute = do
            string "/"
            ownerSlug <- parseText
            string "/"
            repositoryName <- parseText
            string "/tree/"
            branchName <- parseText
            treePath <-
                (do
                    string "/"
                    remainingText
                    )
                    <|> pure ""
            endOfInput
            onlyAllowMethods [GET, HEAD]
            pure RepositoryTreeAction { ownerSlug, repositoryName, branchName, treePath }

        showRepositoryRoute = do
            string "/"
            ownerSlug <- parseText
            string "/"
            repositoryName <- parseText
            endOfInput
            onlyAllowMethods [GET, HEAD]
            pure ShowRepositoryAction { ownerSlug, repositoryName }

    customPathTo ShowRepositoryAction { ownerSlug, repositoryName } =
        Just ("/" <> ownerSlug <> "/" <> repositoryName)
    customPathTo RepositoryTreeAction { ownerSlug, repositoryName, branchName, treePath } =
        Just
            ("/" <> ownerSlug <> "/" <> repositoryName <> "/tree/" <> branchName <> treePathSuffix treePath)
    customPathTo RepositoryPullRequestsAction { ownerSlug, repositoryName } =
        Just ("/" <> ownerSlug <> "/" <> repositoryName <> "/pull-requests")
    customPathTo RepositoryAgentsAction { ownerSlug, repositoryName } =
        Just ("/" <> ownerSlug <> "/" <> repositoryName <> "/agents")
    customPathTo _ = Nothing

treePathSuffix :: Text -> Text
treePathSuffix treePath =
    if Text.null treePath then "" else "/" <> treePath
