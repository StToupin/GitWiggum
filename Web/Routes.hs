module Web.Routes where
import qualified Data.Text as Text
import IHP.RouterPrelude
import Text.Read (readMaybe)
import Generated.Types
import Web.Types

-- Generator Marker
instance AutoRoute StaticController
instance AutoRoute RegistrationsController
instance AutoRoute ConfirmationsController
instance AutoRoute SessionsController
instance AutoRoute PasswordResetsController
instance AutoRoute DashboardController

instance AutoRoute AccountSettingsController where
    customRoutes =
        (do
            string "/settings/ssh"
            endOfInput
            onlyAllowMethods [GET, HEAD]
            pure AccountSshSettingsAction
        )
            <|> (do
                    string "/settings/ssh"
                    endOfInput
                    onlyAllowMethods [POST]
                    pure UpdateAccountSshSettingsAction
                )

    customPathTo AccountSshSettingsAction = Just "/settings/ssh"
    customPathTo UpdateAccountSshSettingsAction = Just "/settings/ssh"

instance AutoRoute GitHttpController where
    customRoutes = do
        onlyAllowMethods [GET, HEAD, POST]
        string "/"
        ownerSlug <- parseText
        string "/"
        repositorySegment <- parseText
        gitPathInfo <- remainingText
        repositoryName <- parseGitHttpRepositorySegment repositorySegment
        pure RepositoryGitHttpAction { ownerSlug, repositoryName, gitPathInfo }

    customPathTo RepositoryGitHttpAction { ownerSlug, repositoryName, gitPathInfo } =
        Just ("/" <> ownerSlug <> "/" <> repositoryName <> ".git" <> gitPathInfo)

instance AutoRoute PullRequestsController where
    customRoutes =
        newPullRequestRoute
            <|> createPullRequestRoute
            <|> showPullRequestConversationRoute
      where
        newPullRequestRoute = do
            string "/"
            ownerSlug <- parseText
            string "/"
            repositoryName <- parseText
            string "/pull-requests/new"
            endOfInput
            onlyAllowMethods [GET, HEAD]
            pure NewPullRequestAction { ownerSlug, repositoryName }

        createPullRequestRoute = do
            string "/"
            ownerSlug <- parseText
            string "/"
            repositoryName <- parseText
            string "/pull-requests/new"
            endOfInput
            onlyAllowMethods [POST]
            pure CreatePullRequestAction { ownerSlug, repositoryName }

        showPullRequestConversationRoute = do
            string "/"
            ownerSlug <- parseText
            string "/"
            repositoryName <- parseText
            string "/pull-requests/"
            pullRequestNumber <- parseRouteNumber
            string "/conversation"
            endOfInput
            onlyAllowMethods [GET, HEAD]
            pure ShowPullRequestConversationAction { ownerSlug, repositoryName, pullRequestNumber }

    customPathTo NewPullRequestAction { ownerSlug, repositoryName } =
        Just ("/" <> ownerSlug <> "/" <> repositoryName <> "/pull-requests/new")
    customPathTo CreatePullRequestAction { ownerSlug, repositoryName } =
        Just ("/" <> ownerSlug <> "/" <> repositoryName <> "/pull-requests/new")
    customPathTo ShowPullRequestConversationAction { ownerSlug, repositoryName, pullRequestNumber } =
        Just ("/" <> ownerSlug <> "/" <> repositoryName <> "/pull-requests/" <> tshow pullRequestNumber <> "/conversation")
    customPathTo _ = Nothing

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

parseGitHttpRepositorySegment :: Text -> Parser Text
parseGitHttpRepositorySegment repositorySegment =
    let suffix = ".git"
     in if suffix `Text.isSuffixOf` repositorySegment
            then pure (Text.dropEnd (Text.length suffix) repositorySegment)
            else empty

treePathSuffix :: Text -> Text
treePathSuffix treePath =
    if Text.null treePath then "" else "/" <> treePath

parseRouteNumber :: Parser Int
parseRouteNumber = do
    value <- parseText

    case readMaybe (cs value) of
        Just number -> pure number
        Nothing -> empty
