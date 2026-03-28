module Web.View.Registrations.New where

import IHP.ValidationSupport.Types (getValidationFailure)
import Web.View.Prelude

data NewView = NewView { user :: User }

instance View NewView where
    html NewView { user } = [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-lg-7 col-xl-6">
                <div class="card shadow-sm border-0">
                    <div class="card-body p-4 p-lg-5">
                        <div class="mb-4">
                            <div class="text-uppercase small fw-semibold text-secondary mb-2">Sign up</div>
                            <h1 class="h2 mb-2">Create your GitWiggum account</h1>
                            <p class="text-secondary mb-0">
                                Accounts stay inactive until the email address is confirmed.
                            </p>
                        </div>

                        <form method="POST" action={pathTo CreateRegistrationAction} class="d-grid gap-3">
                            <div>
                                <label class="form-label" for="registration-email">Email</label>
                                <input
                                    class={inputClass (isJust (getValidationFailure #email user))}
                                    id="registration-email"
                                    type="email"
                                    name="email"
                                    value={get #email user}
                                    autocomplete="email"
                                    required="required"
                                />
                                {validationFeedback (getValidationFailure #email user)}
                            </div>

                            <div>
                                <label class="form-label" for="registration-username">Username</label>
                                <input
                                    class={inputClass (isJust (getValidationFailure #username user))}
                                    id="registration-username"
                                    type="text"
                                    name="username"
                                    value={get #username user}
                                    autocomplete="username"
                                    required="required"
                                />
                                <div class="form-text">Used for your personal owner namespace later.</div>
                                {validationFeedback (getValidationFailure #username user)}
                            </div>

                            <div>
                                <label class="form-label" for="registration-password">Password</label>
                                <input
                                    class={inputClass (isJust (getValidationFailure #passwordHash user))}
                                    id="registration-password"
                                    type="password"
                                    name="password"
                                    autocomplete="new-password"
                                    required="required"
                                />
                                <div class="form-text">Use at least 8 characters.</div>
                                {validationFeedback (getValidationFailure #passwordHash user)}
                            </div>

                            <button class="btn btn-dark btn-lg mt-2" type="submit" data-posthog-id="registration-submit">
                                Create account
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
