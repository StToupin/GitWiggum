module Web.View.Repositories.Shell
    ( RepositoryShellTab (..)
    , renderRepositoryShell
    ) where

import Web.View.Prelude

data RepositoryShellTab
    = BrowserTab
    | PullRequestsTab
    | AgentsTab
    deriving (Eq, Show)

renderRepositoryShell :: User -> Repository -> RepositoryShellTab -> Html -> Html
renderRepositoryShell owner repository activeTab inner =
    let ownerSlug = get #username owner
        repoName = get #name repository
        httpCloneCommand =
            "git clone '" <> urlTo RepositoryGitHttpAction { ownerSlug, repositoryName = repoName, gitPathInfo = "" } <> "'"
        browserPath =
            pathTo
                ShowRepositoryAction
                    { ownerSlug
                    , repositoryName = repoName
                    }
        pullRequestsPath =
            pathTo
                RepositoryPullRequestsAction
                    { ownerSlug
                    , repositoryName = repoName
                    }
        agentsPath =
            pathTo
                RepositoryAgentsAction
                    { ownerSlug
                    , repositoryName = repoName
                    }
     in [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-xl-8">
                <div class="d-flex flex-column flex-lg-row align-items-lg-center justify-content-between gap-3 mb-4">
                    <div>
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">Repository</div>
                        <h1 class="h2 mb-1">{ownerSlug}/{repoName}</h1>
                        <p class="text-secondary mb-0">{fromMaybe "No description yet." (get #description repository)}</p>
                    </div>
                    <div class="d-flex flex-wrap gap-2">
                        <span class="badge text-bg-light align-self-start">{visibilityLabel repository}</span>
                        <a class="btn btn-outline-dark" href={pathTo DashboardAction} data-posthog-id="repository-show-dashboard">
                            Back to dashboard
                        </a>
                    </div>
                </div>

                <div class="d-flex flex-wrap gap-2 mb-4">
                    <a class={tabClass activeTab BrowserTab} href={browserPath} data-posthog-id="repository-shell-browser">
                        Browser
                    </a>
                    <a class={tabClass activeTab PullRequestsTab} href={pullRequestsPath} data-posthog-id="repository-shell-pull-requests">
                        Pull requests
                    </a>
                    <a class={tabClass activeTab AgentsTab} href={agentsPath} data-posthog-id="repository-shell-agents">
                        Agents
                    </a>
                </div>

                <div class="card shadow-sm border-0 mb-4">
                    <div class="card-body p-4">
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">Clone over HTTP</div>
                        <code>{httpCloneCommand}</code>
                    </div>
                </div>

                {inner}
            </div>
        </div>
    |]

tabClass :: RepositoryShellTab -> RepositoryShellTab -> Text
tabClass activeTab tab =
    if activeTab == tab
        then "btn btn-dark"
        else "btn btn-outline-dark"

visibilityLabel :: Repository -> Text
visibilityLabel repository =
    if get #isPrivate repository then "Private" else "Public"
