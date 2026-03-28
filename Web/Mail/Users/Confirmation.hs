module Web.Mail.Users.Confirmation where

import Generated.Types
import IHP.AuthSupport.Confirm (ConfirmationMail (..))
import IHP.MailPrelude
import Web.Types

instance BuildMail (ConfirmationMail User) where
    subject = "Confirm your GitWiggum account"

    to ConfirmationMail { user } =
        Address (Just (get #username user)) (get #email user)

    from =
        Address (Just "GitWiggum") "noreply@gitwiggum.local"

    html mail =
        let confirmationLink = confirmationUrl mail
         in [hsx|
            <p>Welcome to GitWiggum.</p>
            <p>Confirm your account before signing in.</p>
            <p>
                <a href={confirmationLink}>Confirm account</a>
            </p>
            <p>{confirmationLink}</p>
        |]

    text mail =
        "Welcome to GitWiggum.\n\nConfirm your account before signing in:\n"
            <> confirmationUrl mail
            <> "\n"

confirmationUrl :: ConfirmationMail User -> Text
confirmationUrl ConfirmationMail { user, confirmationToken } =
    "http://127.0.0.1:8000/ConfirmUser?userId="
        <> tshow (get #id user)
        <> "&confirmationToken="
        <> confirmationToken
