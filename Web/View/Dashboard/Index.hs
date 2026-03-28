module Web.View.Dashboard.Index where

import Web.View.Prelude

data IndexView = IndexView

instance View IndexView where
    html IndexView = [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-xl-8">
                <div class="d-flex flex-column flex-lg-row align-items-lg-center justify-content-between gap-3 mb-4">
                    <div>
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">Dashboard</div>
                        <h1 class="h2 mb-1">Signed in as {get #username currentUser}</h1>
                        <p class="text-secondary mb-0">Repositories and pull requests will land here next.</p>
                    </div>
                    <a class="btn btn-outline-dark" href={pathTo HomeAction} data-posthog-id="dashboard-home">
                        Back to home
                    </a>
                </div>

                <div class="card shadow-sm border-0 bg-body-tertiary">
                    <div class="card-body p-4">
                        <h2 class="h5 mb-2">No repositories yet</h2>
                        <p class="text-secondary mb-0">
                            Account auth is live. Repository creation is the next slice.
                        </p>
                    </div>
                </div>
            </div>
        </div>
    |]
