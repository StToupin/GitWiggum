module Web.Controller.PasswordResets where

import qualified Data.Char as Char
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDV4
import Data.Time.Clock (addUTCTime, getCurrentTime)
import IHP.AuthSupport.Authentication (hashPassword)
import IHP.MailPrelude (sendMail)
import Web.Controller.Prelude
import Web.Mail.Users.PasswordReset
import Web.View.PasswordResets.Edit
import Web.View.PasswordResets.New

instance Controller PasswordResetsController where
    action NewPasswordResetAction = render NewView { email = "" }

    action CreatePasswordResetAction = do
        let email = normalizeEmail (param @Text "email")

        query @User
            |> filterWhere (#email, email)
            |> fetchOneOrNothing
            >>= \case
                Just user -> do
                    token <- UUID.toText <$> UUIDV4.nextRandom
                    expiresAt <- addUTCTime (60 * 60) <$> getCurrentTime
                    updatedUser <-
                        user
                            |> set #passwordResetToken (Just token)
                            |> set #passwordResetTokenExpiresAt (Just expiresAt)
                            |> updateRecord
                    sendMail PasswordResetMail { user = updatedUser, resetToken = token }
                Nothing -> pure ()

        setSuccessMessage "If an account exists for that email, we sent a password reset link."
        redirectTo NewSessionAction

    action EditPasswordResetAction { userId, passwordResetToken } =
        withValidResetUser userId passwordResetToken \_ ->
            render EditView { userId, passwordResetToken, passwordError = Nothing }

    action UpdatePasswordResetAction { userId, passwordResetToken } =
        withValidResetUser userId passwordResetToken \user -> do
            let password = param @Text "password"

            case validatePasswordInput password of
                Just passwordError ->
                    render EditView { userId, passwordResetToken, passwordError = Just passwordError }
                Nothing -> do
                    passwordHash <- hashPassword password
                    user
                        |> set #passwordHash passwordHash
                        |> set #passwordResetToken Nothing
                        |> set #passwordResetTokenExpiresAt Nothing
                        |> updateRecord
                    setSuccessMessage "Your password has been reset. Sign in with your new password."
                    redirectTo NewSessionAction

withValidResetUser ::
    ( ?context :: ControllerContext
    , ?modelContext :: ModelContext
    , ?request :: Request
    , ?respond :: Respond
    ) =>
    Id User ->
    Text ->
    (User -> IO ()) ->
    IO ()
withValidResetUser userId passwordResetToken handleUser = do
    currentTime <- getCurrentTime
    userOrNothing <-
        query @User
            |> filterWhere (#id, userId)
            |> filterWhere (#passwordResetToken, Just passwordResetToken)
            |> fetchOneOrNothing

    case userOrNothing of
        Just user
            | maybe False (> currentTime) (get #passwordResetTokenExpiresAt user) ->
                handleUser user
        _ -> do
            setErrorMessage "This password reset link is invalid or expired."
            redirectTo NewPasswordResetAction

normalizeEmail :: Text -> Text
normalizeEmail = Text.toLower . Text.strip

validatePasswordInput :: Text -> Maybe Text
validatePasswordInput password
    | Text.length password < 8 = Just "Password must be at least 8 characters"
    | Text.any Char.isSpace password = Just "Password cannot contain spaces"
    | otherwise = Nothing
