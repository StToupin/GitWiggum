module Web.View.Repositories.Show where

import Web.View.Prelude

data ShowView = ShowView
    { owner :: User
    , repository :: Repository
    }

instance View ShowView where
    html ShowView { owner, repository } = [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-xl-8">
                <div class="d-flex flex-column flex-lg-row align-items-lg-center justify-content-between gap-3 mb-4">
                    <div>
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">Repository</div>
                        <h1 class="h2 mb-1">{get #username owner}/{get #name repository}</h1>
                        <p class="text-secondary mb-0">{fromMaybe "No description yet." (get #description repository)}</p>
                    </div>
                    <div class="d-flex flex-wrap gap-2">
                        <span class="badge text-bg-light align-self-start">{visibilityLabel repository}</span>
                        <a class="btn btn-outline-dark" href={pathTo DashboardAction} data-posthog-id="repository-show-dashboard">
                            Back to dashboard
                        </a>
                    </div>
                </div>

                <div class="card shadow-sm border-0 bg-body-tertiary">
                    <div class="card-body p-4">
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">Next</div>
                        <p class="mb-0 text-secondary">
                            This repository route is live and canonical. The repository shell, initial git data, and browser
                            tabs land in the next slices.
                        </p>
                    </div>
                </div>
            </div>
        </div>
    |]

visibilityLabel :: Repository -> Text
visibilityLabel repository =
    if get #isPrivate repository then "Private" else "Public"
