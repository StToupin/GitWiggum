module Web.FrontController where

import IHP.RouterPrelude
import Web.Controller.Prelude
import Web.View.Layout (defaultLayout)

-- Controller Imports
import Web.Controller.Static
import Web.Controller.Registrations

instance FrontController WebApplication where
    controllers = 
        [ startPage HomeAction
        , parseRoute @StaticController
        , parseRoute @RegistrationsController
        -- Generator Marker
        ]

instance InitControllerContext WebApplication where
    initContext = do
        setLayout defaultLayout
