module Web.View.PasswordResets.New where

import Web.View.Prelude

data NewView = NewView { email :: Text }

instance View NewView where
    html NewView { email } = [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-lg-6 col-xl-5">
                <div class="card shadow-sm border-0">
                    <div class="card-body p-4 p-lg-5">
                        <div class="mb-4">
                            <div class="text-uppercase small fw-semibold text-secondary mb-2">Password reset</div>
                            <h1 class="h2 mb-2">Reset your password</h1>
                            <p class="text-secondary mb-0">
                                Enter your email and we will send a reset link if the account exists.
                            </p>
                        </div>

                        <form method="POST" action={pathTo CreatePasswordResetAction} class="d-grid gap-3">
                            <div>
                                <label class="form-label" for="password-reset-email">Email</label>
                                <input
                                    class="form-control"
                                    id="password-reset-email"
                                    type="email"
                                    name="email"
                                    value={email}
                                    autocomplete="email"
                                    required="required"
                                />
                            </div>

                            <button class="btn btn-dark btn-lg mt-2" type="submit" data-posthog-id="password-reset-request-submit">
                                Send reset link
                            </button>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    |]
