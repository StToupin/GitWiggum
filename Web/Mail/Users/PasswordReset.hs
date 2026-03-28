module Web.Mail.Users.PasswordReset where

import Generated.Types
import IHP.MailPrelude
import Web.Types

data PasswordResetMail user = PasswordResetMail
    { user :: user
    , resetToken :: Text
    }

instance BuildMail (PasswordResetMail User) where
    subject = "Reset your GitWiggum password"

    to PasswordResetMail { user } =
        Address (Just (get #username user)) (get #email user)

    from =
        Address (Just "GitWiggum") "noreply@gitwiggum.local"

    html mail = [hsx|
        <p>We received a request to reset your GitWiggum password.</p>
        <p>
            <a href={passwordResetUrl mail}>Reset your password</a>
        </p>
        <p>
            Your reset token is:
            <code>{mail.resetToken}</code>
        </p>
        <p>This token expires in one hour.</p>
    |]

    text mail =
        "We received a request to reset your GitWiggum password.\n\nReset link: "
            <> passwordResetUrl mail
            <> "\n\nReset token: "
            <> mail.resetToken
            <> "\n\nThis token expires in one hour.\n"

passwordResetUrl :: PasswordResetMail User -> Text
passwordResetUrl PasswordResetMail { user, resetToken } =
    "http://127.0.0.1:8000/EditPasswordReset?userId="
        <> tshow (get #id user)
        <> "&passwordResetToken="
        <> resetToken
