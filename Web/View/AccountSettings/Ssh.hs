module Web.View.AccountSettings.Ssh where

import Web.View.Prelude

data SshSettingsFormState = SshSettingsFormState
    { sshPublicKey :: Text
    , validationError :: Maybe Text
    }

data SshSettingsView = SshSettingsView
    { formState :: SshSettingsFormState
    , hasConfiguredKey :: Bool
    }

instance View SshSettingsView where
    html SshSettingsView { formState = SshSettingsFormState { sshPublicKey, validationError }, hasConfiguredKey } = [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-lg-8 col-xl-7">
                <div class="d-flex flex-column flex-lg-row align-items-lg-center justify-content-between gap-3 mb-4">
                    <div>
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">Account settings</div>
                        <h1 class="h2 mb-1">SSH keys</h1>
                        <p class="text-secondary mb-0">
                            Save one SSH public key for future SSH clone and push access.
                        </p>
                    </div>
                    <span class={statusBadgeClass hasConfiguredKey}>
                        {statusLabel hasConfiguredKey}
                    </span>
                </div>

                <div class="card shadow-sm border-0">
                    <div class="card-body p-4">
                        <form method="POST" action={pathTo UpdateAccountSshSettingsAction} class="d-grid gap-3">
                            <div>
                                <label class="form-label" for="account-ssh-public-key">SSH public key</label>
                                <textarea
                                    class={textareaClass validationError}
                                    id="account-ssh-public-key"
                                    name="sshPublicKey"
                                    rows="6"
                                    spellcheck="false"
                                    placeholder="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA..."
                                >{sshPublicKey}</textarea>
                                <div class="form-text">
                                    Paste one public key. Save an empty value to remove it.
                                </div>
                                {renderValidationError validationError}
                            </div>

                            <button class="btn btn-dark" type="submit" data-posthog-id="account-ssh-save">
                                Save SSH key
                            </button>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    |]

statusLabel :: Bool -> Text
statusLabel True = "Configured"
statusLabel False = "Not configured"

statusBadgeClass :: Bool -> Text
statusBadgeClass True = "badge text-bg-success"
statusBadgeClass False = "badge text-bg-light"

textareaClass :: Maybe Text -> Text
textareaClass validationError =
    if isJust validationError
        then "form-control is-invalid font-monospace"
        else "form-control font-monospace"

renderValidationError :: Maybe Text -> Html
renderValidationError Nothing = mempty
renderValidationError (Just validationError) = [hsx|
    <div class="invalid-feedback d-block">{validationError}</div>
|]
