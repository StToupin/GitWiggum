module Web.View.PasswordResets.Edit where

import Web.View.Prelude

data EditView = EditView
    { userId :: Id User
    , passwordResetToken :: Text
    , passwordError :: Maybe Text
    }

instance View EditView where
    html view@EditView { passwordError } =
        let formAction =
                pathTo
                    UpdatePasswordResetAction
                        { userId = view.userId
                        , passwordResetToken = view.passwordResetToken
                        }
         in [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-lg-6 col-xl-5">
                <div class="card shadow-sm border-0">
                    <div class="card-body p-4 p-lg-5">
                        <div class="mb-4">
                            <div class="text-uppercase small fw-semibold text-secondary mb-2">Password reset</div>
                            <h1 class="h2 mb-2">Choose a new password</h1>
                            <p class="text-secondary mb-0">
                                Set a new password for your GitWiggum account.
                            </p>
                        </div>

                        <form method="POST" action={formAction} class="d-grid gap-3">
                            <div>
                                <label class="form-label" for="password-reset-new-password">New password</label>
                                <input
                                    class={inputClass (isJust passwordError)}
                                    id="password-reset-new-password"
                                    type="password"
                                    name="password"
                                    autocomplete="new-password"
                                    required="required"
                                />
                                <div class="form-text">Use at least 8 characters and avoid spaces.</div>
                                {validationFeedback passwordError}
                            </div>

                            <button class="btn btn-dark btn-lg mt-2" type="submit" data-posthog-id="password-reset-completion-submit">
                                Update password
                            </button>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    |]

inputClass :: Bool -> Text
inputClass hasError =
    "form-control" <> if hasError then " is-invalid" else ""

validationFeedback :: Maybe Text -> Html
validationFeedback (Just text) = [hsx|<div class="invalid-feedback d-block">{text}</div>|]
validationFeedback Nothing = mempty
