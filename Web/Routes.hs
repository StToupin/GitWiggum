module Web.Routes where
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
    customRoutes = showRepositoryRoute
      where
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
    customPathTo _ = Nothing
