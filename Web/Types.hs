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

data DashboardController
    = DashboardAction
    deriving (Eq, Show, Data)

type instance CurrentUserRecord = User

instance HasNewSessionUrl User where
    newSessionUrl _ = "/NewSession"
