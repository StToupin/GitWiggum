module Web.View.Repositories.PullRequests where

import Web.View.Prelude
import Web.View.Repositories.Shell

data PullRequestsView = PullRequestsView
    { owner :: User
    , repository :: Repository
    , pullRequests :: [PullRequest]
    }

instance View PullRequestsView where
    html PullRequestsView { owner, repository, pullRequests } =
        let ownerSlug = get #username owner
            repositoryName = get #name repository
            newPullRequestPath =
                pathTo
                    NewPullRequestAction
                        { ownerSlug = ownerSlug
                        , repositoryName = repositoryName
                        }
         in
            renderRepositoryShell owner repository PullRequestsTab [hsx|
            <div class="d-flex flex-column flex-lg-row align-items-lg-center justify-content-between gap-3 mb-4">
                <div>
                    <div class="text-uppercase small fw-semibold text-secondary mb-2">Pull requests</div>
                    <h2 class="h5 mb-1">Pull requests</h2>
                    <p class="text-secondary mb-0">
                        Review open work and start a new pull request from any pushed branch.
                    </p>
                </div>
                <a
                    class="btn btn-dark"
                    href={newPullRequestPath}
                    data-posthog-id="pull-requests-new"
                >
                    New pull request
                </a>
            </div>

            {renderPullRequestList owner repository pullRequests}
        |]

renderPullRequestList :: User -> Repository -> [PullRequest] -> Html
renderPullRequestList owner repository [] = [hsx|
    <div class="card shadow-sm border-0">
        <div class="card-body p-4">
            <h3 class="h6 mb-2">No pull requests yet</h3>
            <p class="text-secondary mb-0">
                Push a compare branch, then open a pull request to start review.
            </p>
        </div>
    </div>
|]
renderPullRequestList owner repository pullRequests =
    let ownerSlug = get #username owner
        repositoryName = get #name repository
     in [hsx|
        <div class="card shadow-sm border-0">
            <div class="list-group list-group-flush">
                {forEach pullRequests (renderPullRequestRow ownerSlug repositoryName)}
            </div>
        </div>
    |]

renderPullRequestRow :: Text -> Text -> PullRequest -> Html
renderPullRequestRow ownerSlug repositoryName pullRequest =
    let conversationPath =
            pathTo
                ShowPullRequestConversationAction
                    { ownerSlug = ownerSlug
                    , repositoryName = repositoryName
                    , pullRequestNumber = get #number pullRequest
                    }
     in [hsx|
        <a
            class="list-group-item list-group-item-action p-4"
            href={conversationPath}
            data-posthog-id="pull-request-row-link"
        >
            <div class="d-flex flex-column flex-lg-row align-items-lg-center justify-content-between gap-3">
                <div>
                    <div class="d-flex flex-wrap align-items-center gap-2 mb-2">
                        <span class={stateBadgeClass pullRequest}>{pullRequestStateLabel pullRequest}</span>
                        {draftBadge pullRequest}
                        <code>{pullRequestNumberLabel pullRequest}</code>
                    </div>
                    <div class="fw-semibold">{get #title pullRequest}</div>
                    <div class="text-secondary small mt-1">
                        {pullRequestBranchSummary pullRequest}
                    </div>
                </div>
            </div>
        </a>
    |]

pullRequestStateLabel :: PullRequest -> Text
pullRequestStateLabel pullRequest =
    if get #state pullRequest == "open" then "Open" else cs (get #state pullRequest)

stateBadgeClass :: PullRequest -> Text
stateBadgeClass pullRequest =
    if get #state pullRequest == "open"
        then "badge text-bg-success"
        else "badge text-bg-secondary"

draftBadge :: PullRequest -> Html
draftBadge pullRequest
    | get #isDraft pullRequest = [hsx|<span class="badge text-bg-light">Draft</span>|]
    | otherwise = mempty

pullRequestNumberLabel :: PullRequest -> Text
pullRequestNumberLabel pullRequest = "#" <> tshow (get #number pullRequest)

pullRequestBranchSummary :: PullRequest -> Text
pullRequestBranchSummary pullRequest =
    get #baseBranch pullRequest <> " <- " <> get #compareBranch pullRequest
