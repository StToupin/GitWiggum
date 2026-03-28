module Web.Types where

import IHP.Prelude
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
