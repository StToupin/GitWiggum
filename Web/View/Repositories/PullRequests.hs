module Web.View.Repositories.PullRequests where

import Web.View.Prelude
import Web.View.Repositories.Shell

data PullRequestsView = PullRequestsView
    { owner :: User
    , repository :: Repository
    }

instance View PullRequestsView where
    html PullRequestsView { owner, repository } =
        renderRepositoryShell owner repository PullRequestsTab [hsx|
            <div class="card shadow-sm border-0">
                <div class="card-body p-4">
                    <div class="text-uppercase small fw-semibold text-secondary mb-2">Pull requests</div>
                    <h2 class="h5 mb-1">Repository pull request surface</h2>
                    <p class="text-secondary mb-0">
                        This dedicated route already preserves the repository context. The pull request list lands in the next slice.
                    </p>
                </div>
            </div>
        |]
