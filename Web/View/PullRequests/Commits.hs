module Web.View.PullRequests.Commits where

import Application.Service.GitRepository
import qualified Data.Text as Text
import Web.View.Prelude
import Web.View.PullRequests.Shell

data CommitsView = CommitsView
    { owner :: User
    , repository :: Repository
    , pullRequest :: PullRequest
    , author :: User
    , commits :: [GitPullRequestCommit]
    }

instance View CommitsView where
    html CommitsView { owner, repository, pullRequest, author, commits } =
        renderPullRequestShell owner repository pullRequest author CommitsTab [hsx|
            <div class="card shadow-sm border-0">
                <div class="card-body p-4">
                    <div class="d-flex flex-wrap align-items-center justify-content-between gap-3 mb-3">
                        <div>
                            <div class="text-uppercase small fw-semibold text-secondary mb-2">Commits</div>
                            <h3 class="h5 mb-0">Compare range commits</h3>
                        </div>
                        <span class="badge text-bg-light">{tshow (length commits)} commits</span>
                    </div>

                    {renderCommitList commits}
                </div>
            </div>
        |]

renderCommitList :: [GitPullRequestCommit] -> Html
renderCommitList [] = [hsx|
    <div class="border rounded-3 p-3 text-secondary">
        No commits are in the compare range.
    </div>
|]
renderCommitList commits = [hsx|
    <div class="list-group list-group-flush">
        {forEach commits renderCommitRow}
    </div>
|]

renderCommitRow :: GitPullRequestCommit -> Html
renderCommitRow GitPullRequestCommit { commitSha, commitSubject } = [hsx|
    <div class="list-group-item px-0 py-3">
        <div class="d-flex flex-column flex-lg-row align-items-lg-center justify-content-between gap-2">
            <div>
                <div class="fw-semibold">{subjectLabel commitSubject}</div>
                <div class="text-secondary small mt-1">
                    Commit <code>{Text.take 10 commitSha}</code>
                </div>
            </div>
        </div>
    </div>
|]

subjectLabel :: Text -> Text
subjectLabel commitSubject =
    if Text.null commitSubject then "No commit subject" else commitSubject
