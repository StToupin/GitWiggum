module Web.Types where

import IHP.Prelude
import IHP.LoginSupport.Types (CurrentUserRecord, HasNewSessionUrl (..))
import IHP.ModelSupport
import Generated.Types

data WebApplication = WebApplication deriving (Eq, Show)


data StaticController
    = HomeAction
    deriving (Eq, Show, Data)

data RegistrationsController
    = NewRegistrationAction
    | CreateRegistrationAction
    deriving (Eq, Show, Data)

data ConfirmationsController
    = ConfirmUserAction { userId :: !(Id User), confirmationToken :: !Text }
    deriving (Eq, Show, Data)

data SessionsController
    = NewSessionAction
    | CreateSessionAction
    | LogoutAction
    deriving (Eq, Show, Data)

data PasswordResetsController
    = NewPasswordResetAction
    | CreatePasswordResetAction
    | EditPasswordResetAction { userId :: !(Id User), passwordResetToken :: !Text }
    | UpdatePasswordResetAction { userId :: !(Id User), passwordResetToken :: !Text }
    deriving (Eq, Show, Data)

data DashboardController
    = DashboardAction
    deriving (Eq, Show, Data)

data GitHttpController
    = RepositoryGitHttpAction { ownerSlug :: !Text, repositoryName :: !Text, gitPathInfo :: !Text }
    deriving (Eq, Show, Data)

data RepositoriesController
    = NewRepositoryAction
    | CreateRepositoryAction
    | ShowRepositoryAction { ownerSlug :: !Text, repositoryName :: !Text }
    | RepositoryTreeAction { ownerSlug :: !Text, repositoryName :: !Text, branchName :: !Text, treePath :: !Text }
    | RepositoryPullRequestsAction { ownerSlug :: !Text, repositoryName :: !Text }
    | RepositoryAgentsAction { ownerSlug :: !Text, repositoryName :: !Text }
    deriving (Eq, Show, Data)

type instance CurrentUserRecord = User

instance HasNewSessionUrl User where
    newSessionUrl _ = "/NewSession"
