module Web.View.Repositories.New where

import Web.View.Prelude

data NewView = NewView

instance View NewView where
    html NewView = [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-lg-7 col-xl-6">
                <div class="card shadow-sm border-0">
                    <div class="card-body p-4 p-lg-5">
                        <div class="mb-4">
                            <div class="text-uppercase small fw-semibold text-secondary mb-2">Repositories</div>
                            <h1 class="h2 mb-2">Create repository</h1>
                            <p class="text-secondary mb-0">
                                This owner namespace is ready for repository creation:
                                <code class="ms-1">{ownerNamespacePath currentUser}</code>
                            </p>
                        </div>

                        <div class="alert alert-light border mb-4">
                            The repository form lands in the next slice. This page already anchors the dashboard CTA so
                            repository creation can stay page-like.
                        </div>

                        <a class="btn btn-outline-dark" href={pathTo DashboardAction} data-posthog-id="repository-new-back-dashboard">
                            Back to dashboard
                        </a>
                    </div>
                </div>
            </div>
        </div>
    |]
