module Web.Controller.PasswordResets where

import qualified Data.Text as Text
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDV4
import Data.Time.Clock (addUTCTime, getCurrentTime)
import IHP.MailPrelude (sendMail)
import Web.Controller.Prelude
import Web.Mail.Users.PasswordReset
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
      where
        normalizeEmail = Text.toLower . Text.strip
