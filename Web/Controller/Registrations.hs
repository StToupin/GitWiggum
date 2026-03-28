module Web.Controller.Registrations where

import qualified Data.Char as Char
import qualified Data.Text as Text
import IHP.AuthSupport.Authentication (hashPassword)
import IHP.ValidationSupport.Types (attachFailure, getValidationFailure, isFailure)
import IHP.ValidationSupport.ValidateField (hasMinLength, isEmail, isSlug, nonEmpty, validateField)
import IHP.ValidationSupport.ValidateIsUnique (validateIsUnique, validateIsUniqueCaseInsensitive)
import Web.Controller.Prelude
import Web.View.Registrations.New

instance Controller RegistrationsController where
    action NewRegistrationAction = do
        let user = newRecord @User
        render NewView { user }

    action CreateRegistrationAction = do
        let password = param @Text "password"
        passwordHash <- hashPassword password

        user <-
            newRecord @User
                |> set #email (param @Text "email")
                |> set #username (param @Text "username")
                |> set #passwordHash passwordHash
                |> validateField #email nonEmpty
                |> validateField #email isEmail
                |> validateField #username nonEmpty
                |> validateField #username isSlug
                |> validateIsUniqueCaseInsensitive #email
                >>= validateIsUnique #username
                >>= pure . validatePassword password

        if hasRegistrationErrors user
            then render NewView { user }
            else do
                user |> createRecord
                setSuccessMessage "Account created. Confirm your email before signing in."
                redirectTo HomeAction
      where
        validatePassword password user
            | isNothing (getValidationFailure #passwordHash user) && isFailure (hasMinLength 8 password) =
                user |> attachFailure #passwordHash "Password must be at least 8 characters"
            | Text.any Char.isSpace password =
                user |> attachFailure #passwordHash "Password cannot contain spaces"
            | otherwise =
                user

        hasRegistrationErrors user =
            isJust (getValidationFailure #email user)
                || isJust (getValidationFailure #username user)
                || isJust (getValidationFailure #passwordHash user)
