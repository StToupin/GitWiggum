module Web.FrontController where

import IHP.RouterPrelude
import IHP.LoginSupport.Middleware (initAuthentication)
import Web.Controller.Prelude
import Web.View.Layout (defaultLayout)

-- Controller Imports
import Web.Controller.Static
import Web.Controller.Confirmations
import Web.Controller.Registrations
import Web.Controller.Sessions
import Web.Controller.Dashboard

instance FrontController WebApplication where
    controllers = 
        [ startPage HomeAction
        , parseRoute @StaticController
        , parseRoute @RegistrationsController
        , parseRoute @ConfirmationsController
        , parseRoute @SessionsController
        , parseRoute @DashboardController
        -- Generator Marker
        ]

instance InitControllerContext WebApplication where
    initContext = do
        initAuthentication @User
        setLayout defaultLayout
