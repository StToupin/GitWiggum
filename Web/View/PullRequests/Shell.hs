module Web.View.PullRequests.Shell
    ( PullRequestDetailTab (..)
    , renderPullRequestShell
    ) where

import Web.View.Prelude
import Web.View.Repositories.Shell

data PullRequestDetailTab
    = ConversationTab
    | CommitsTab
    | FilesTab
    deriving (Eq, Show)

renderPullRequestShell :: User -> Repository -> PullRequest -> User -> PullRequestDetailTab -> Html -> Html
renderPullRequestShell owner repository pullRequest author activeTab inner =
    let ownerSlug = get #username owner
        repositoryName = get #name repository
        pullRequestsPath =
            pathTo
                RepositoryPullRequestsAction
                    { ownerSlug = ownerSlug
                    , repositoryName = repositoryName
                    }
        conversationPath =
            pathTo
                ShowPullRequestConversationAction
                    { ownerSlug = ownerSlug
                    , repositoryName = repositoryName
                    , pullRequestNumber = get #number pullRequest
                    }
        commitsPath =
            pathTo
                ShowPullRequestCommitsAction
                    { ownerSlug = ownerSlug
                    , repositoryName = repositoryName
                    , pullRequestNumber = get #number pullRequest
                    }
        filesPath =
            pathTo
                ShowPullRequestFilesAction
                    { ownerSlug = ownerSlug
                    , repositoryName = repositoryName
                    , pullRequestNumber = get #number pullRequest
                    }
     in
        renderRepositoryShell owner repository PullRequestsTab [hsx|
            <div class="d-flex flex-column flex-lg-row align-items-lg-center justify-content-between gap-3 mb-4">
                <div>
                    <div class="text-uppercase small fw-semibold text-secondary mb-2">Pull request</div>
                    <h2 class="h4 mb-1">{pullRequestHeading pullRequest}</h2>
                    <p class="text-secondary mb-0">
                        {pullRequestBranchSummary pullRequest}
                    </p>
                </div>
                <a
                    class="btn btn-outline-dark"
                    href={pullRequestsPath}
                    data-posthog-id="pull-request-back"
                >
                    Back to pull requests
                </a>
            </div>

            <div class="card shadow-sm border-0 mb-4">
                <div class="card-body p-4">
                    <div class="d-flex flex-wrap align-items-center gap-2 mb-3">
                        <span class={stateBadgeClass pullRequest}>{pullRequestStateLabel pullRequest}</span>
                        {draftBadge pullRequest}
                        <span class="text-secondary small">Opened by {get #username author}</span>
                    </div>

                    <dl class="row mb-0">
                        <dt class="col-sm-3 text-secondary">Base branch</dt>
                        <dd class="col-sm-9"><code>{get #baseBranch pullRequest}</code></dd>

                        <dt class="col-sm-3 text-secondary">Compare branch</dt>
                        <dd class="col-sm-9"><code>{get #compareBranch pullRequest}</code></dd>

                        <dt class="col-sm-3 text-secondary">State</dt>
                        <dd class="col-sm-9">{pullRequestStateLabel pullRequest}</dd>
                    </dl>
                </div>
            </div>

            <div class="d-flex flex-wrap gap-2 mb-4">
                <a
                    class={tabClass activeTab ConversationTab}
                    href={conversationPath}
                    data-posthog-id="pull-request-tab-conversation"
                >
                    Conversation
                </a>
                <a
                    class={tabClass activeTab CommitsTab}
                    href={commitsPath}
                    data-posthog-id="pull-request-tab-commits"
                >
                    Commits
                </a>
                <a
                    class={tabClass activeTab FilesTab}
                    href={filesPath}
                    data-posthog-id="pull-request-tab-files"
                >
                    Files
                </a>
            </div>

            {inner}
        |]

tabClass :: PullRequestDetailTab -> PullRequestDetailTab -> Text
tabClass activeTab tab =
    if activeTab == tab
        then "btn btn-dark"
        else "btn btn-outline-dark"

stateBadgeClass :: PullRequest -> Text
stateBadgeClass pullRequest =
    if get #state pullRequest == "open"
        then "badge text-bg-success"
        else "badge text-bg-secondary"

pullRequestStateLabel :: PullRequest -> Text
pullRequestStateLabel pullRequest =
    if get #state pullRequest == "open" then "Open" else cs (get #state pullRequest)

draftBadge :: PullRequest -> Html
draftBadge pullRequest
    | get #isDraft pullRequest = [hsx|<span class="badge text-bg-light">Draft</span>|]
    | otherwise = mempty

pullRequestHeading :: PullRequest -> Text
pullRequestHeading pullRequest =
    "#" <> tshow (get #number pullRequest) <> " " <> get #title pullRequest

pullRequestBranchSummary :: PullRequest -> Text
pullRequestBranchSummary pullRequest =
    get #baseBranch pullRequest <> " <- " <> get #compareBranch pullRequest
