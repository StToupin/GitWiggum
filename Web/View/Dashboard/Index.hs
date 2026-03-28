module Web.View.Dashboard.Index where

import Web.View.Prelude

data IndexView = IndexView { repositories :: [Repository] }

instance View IndexView where
    html IndexView { repositories } = [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-xl-8">
                <div class="d-flex flex-column flex-lg-row align-items-lg-center justify-content-between gap-3 mb-4">
                    <div>
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">Dashboard</div>
                        <h1 class="h2 mb-1">Signed in as {get #username currentUser}</h1>
                        <p class="text-secondary mb-0">Repositories and pull requests will land here next.</p>
                    </div>
                    <div class="d-flex flex-wrap gap-2">
                        <a class="btn btn-dark" href={pathTo NewRepositoryAction} data-posthog-id="dashboard-create-repository">
                            Create repository
                        </a>
                        <a class="btn btn-outline-dark" href={pathTo HomeAction} data-posthog-id="dashboard-home">
                            Back to home
                        </a>
                    </div>
                </div>

                <div class="row g-4">
                    <div class="col-12 col-lg-5">
                        <div class="card shadow-sm border-0">
                            <div class="card-body p-4">
                                <div class="text-uppercase small fw-semibold text-secondary mb-2">Personal owner namespace</div>
                                <div class="fs-4 fw-semibold mb-2">
                                    <code>{ownerNamespacePath currentUser}</code>
                                </div>
                                <p class="text-secondary mb-0">
                                    Repository creation will default to this owner slug, so canonical routes can start at
                                    <code class="ms-1">{ownerNamespacePath currentUser}</code>.
                                </p>
                            </div>
                        </div>
                    </div>

                    <div class="col-12 col-lg-7">
                        {renderRepositoryPanel repositories}
                    </div>
                </div>
            </div>
        </div>
    |]

renderRepositoryPanel :: [Repository] -> Html
renderRepositoryPanel [] = [hsx|
    <div class="card shadow-sm border-0 bg-body-tertiary h-100">
        <div class="card-body p-4">
            <h2 class="h5 mb-2">No repositories yet</h2>
            <p class="text-secondary mb-0">
                Your namespace is ready. Create the first repository when you are ready.
            </p>
        </div>
    </div>
|]
renderRepositoryPanel repositories = [hsx|
    <div class="card shadow-sm border-0 h-100">
        <div class="card-body p-4">
            <div class="d-flex align-items-center justify-content-between gap-3 mb-3">
                <h2 class="h5 mb-0">Repositories</h2>
                <span class="badge text-bg-light">{tshow (length repositories)}</span>
            </div>
            <div class="d-grid gap-3">
                {forEach repositories renderRepositoryCard}
            </div>
        </div>
    </div>
|]

renderRepositoryCard :: Repository -> Html
renderRepositoryCard repository = [hsx|
    <div class="border rounded-3 p-3">
        <div class="d-flex align-items-center justify-content-between gap-3 mb-2">
            <div class="fw-semibold">{get #name repository}</div>
            <span class="badge rounded-pill text-bg-light">{visibilityLabel repository}</span>
        </div>
        <div class="text-secondary small mb-0">
            {fromMaybe "No description yet." (get #description repository)}
        </div>
    </div>
|]

visibilityLabel :: Repository -> Text
visibilityLabel repository =
    if get #isPrivate repository then "Private" else "Public"
