module Web.Controller.AccountSettings where

import Application.Service.SshKeys
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.View.AccountSettings.Ssh

instance Controller AccountSettingsController where
    beforeAction = ensureIsUser

    action AccountSshSettingsAction =
        renderCurrentSettings Nothing

    action UpdateAccountSshSettingsAction = do
        let submittedSshPublicKey = paramOrDefault "" "sshPublicKey"

        case normalizeSshPublicKey submittedSshPublicKey of
            Left validationError ->
                renderCurrentSettings
                    ( Just
                        SshSettingsFormState
                            { sshPublicKey = Text.strip submittedSshPublicKey
                            , validationError = Just validationError
                            }
                    )
            Right maybePublicKey -> do
                currentUser
                    |> set #sshPublicKey maybePublicKey
                    |> updateRecord

                setSuccessMessage $
                    case maybePublicKey of
                        Just _ -> "SSH public key saved."
                        Nothing -> "SSH public key removed."

                redirectTo AccountSshSettingsAction

renderCurrentSettings ::
    (?context :: ControllerContext, ?request :: Request, ?modelContext :: ModelContext, ?respond :: Respond) =>
    Maybe SshSettingsFormState ->
    IO ()
renderCurrentSettings formStateOrNothing =
    let storedKey = fromMaybe "" (get #sshPublicKey currentUser)
        formState =
            fromMaybe
                SshSettingsFormState
                    { sshPublicKey = storedKey
                    , validationError = Nothing
                    }
                formStateOrNothing
     in render
            SshSettingsView
                { formState
                , hasConfiguredKey = isJust (get #sshPublicKey currentUser)
                }
