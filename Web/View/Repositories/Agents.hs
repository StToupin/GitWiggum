module Web.View.Repositories.Agents where

import Web.View.Prelude
import Web.View.Repositories.Shell

data AgentsView = AgentsView
    { owner :: User
    , repository :: Repository
    }

instance View AgentsView where
    html AgentsView { owner, repository } =
        renderRepositoryShell owner repository AgentsTab [hsx|
            <div class="card shadow-sm border-0">
                <div class="card-body p-4">
                    <div class="text-uppercase small fw-semibold text-secondary mb-2">Agents</div>
                    <h2 class="h5 mb-1">Repository agents surface</h2>
                    <p class="text-secondary mb-0">
                        This dedicated route already preserves the repository context. Prompt-to-draft pull requests land in a later slice.
                    </p>
                </div>
            </div>
        |]
