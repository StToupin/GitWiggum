module Web.View.Sessions.New where

import Web.View.Prelude

data NewView = NewView { email :: Text }

instance View NewView where
    html NewView { email } = [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-lg-6 col-xl-5">
                <div class="card shadow-sm border-0">
                    <div class="card-body p-4 p-lg-5">
                        <div class="mb-4">
                            <div class="text-uppercase small fw-semibold text-secondary mb-2">Sign in</div>
                            <h1 class="h2 mb-2">Continue to GitWiggum</h1>
                            <p class="text-secondary mb-0">
                                Use the email address and password from your confirmed account.
                            </p>
                        </div>

                        <form method="POST" action={pathTo CreateSessionAction} class="d-grid gap-3">
                            <div>
                                <label class="form-label" for="session-email">Email</label>
                                <input
                                    class="form-control"
                                    id="session-email"
                                    type="email"
                                    name="email"
                                    value={email}
                                    autocomplete="email"
                                    required="required"
                                />
                            </div>

                            <div>
                                <label class="form-label" for="session-password">Password</label>
                                <input
                                    class="form-control"
                                    id="session-password"
                                    type="password"
                                    name="password"
                                    autocomplete="current-password"
                                    required="required"
                                />
                            </div>

                            <button class="btn btn-dark btn-lg mt-2" type="submit" data-posthog-id="session-submit">
                                Sign in
                            </button>
                        </form>

                        <div class="mt-4 text-center">
                            <a href={pathTo NewPasswordResetAction} class="text-decoration-none" data-posthog-id="session-forgot-password">
                                Forgot your password?
                            </a>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    |]
