module Web.Controller.Sessions where

import qualified Data.Text as Text
import IHP.AuthSupport.Authentication (verifyPassword)
import Web.Controller.Prelude
import Web.View.Sessions.New

instance Controller SessionsController where
    action NewSessionAction = render NewView { email = "" }

    action CreateSessionAction = do
        let email = normalizeEmail (param @Text "email")
        let password = param @Text "password"

        userOrNothing <-
            query @User
                |> filterWhere (#email, email)
                |> fetchOneOrNothing

        case userOrNothing of
            Just user
                | not (get #isConfirmed user) -> do
                    setErrorMessage "Please confirm your email before logging in."
                    render NewView { email }
                | verifyPassword user password -> do
                    login user
                    setSuccessMessage "Signed in successfully."
                    redirectTo DashboardAction
                | otherwise -> invalidCredentials email
            Nothing -> invalidCredentials email
      where
        invalidCredentials email = do
            setErrorMessage "Invalid email or password."
            render NewView { email }

        normalizeEmail = Text.toLower . Text.strip

    action LogoutAction = do
        case currentUserOrNothing of
            Just user -> logout user
            Nothing -> pure ()
        setSuccessMessage "Signed out."
        redirectTo HomeAction
