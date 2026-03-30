module Web.View.PullRequests.Conversation where

import Web.View.Prelude
import Web.View.PullRequests.ReviewComments
import Web.View.PullRequests.Shell

data ConversationView = ConversationView
    { owner :: User
    , repository :: Repository
    , pullRequest :: PullRequest
    , author :: User
    , reviewComments :: [PullRequestReviewCommentDisplay]
    }

instance View ConversationView where
    html ConversationView{owner, repository, pullRequest, author, reviewComments} =
        let filesPath =
                pathTo
                    ShowPullRequestFilesAction
                        { ownerSlug = get #username owner
                        , repositoryName = get #name repository
                        , pullRequestNumber = get #number pullRequest
                        }
         in renderPullRequestShell
                owner
                repository
                pullRequest
                author
                ConversationTab
                [hsx|
            <div class="d-flex flex-column gap-4">
                <div class="card shadow-sm border-0">
                    <div class="card-body p-4">
                        <div class="border rounded-3 p-3 bg-light-subtle">
                            <div class="text-uppercase small fw-semibold text-secondary mb-2">Description</div>
                            <div>{fromMaybe ("No description yet." :: Text) (get #description pullRequest)}</div>
                        </div>
                    </div>
                </div>

                <div class="card shadow-sm border-0">
                    <div class="card-body p-4">
                        <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
                            <div>
                                <div class="text-uppercase small fw-semibold text-secondary mb-1">Review comments</div>
                                <h3 class="h6 mb-0">Line-level feedback</h3>
                            </div>
                            <span class="badge text-bg-light">{tshow (length reviewComments)} comments</span>
                        </div>

                        {if null reviewComments then emptyReviewCommentsState else renderReviewCommentsList filesPath reviewComments}
                    </div>
                </div>
            </div>
        |]

emptyReviewCommentsState :: Html
emptyReviewCommentsState =
    [hsx|
    <p class="mb-0 text-secondary">No one has left line comments on this pull request yet.</p>
|]

renderReviewCommentsList :: Text -> [PullRequestReviewCommentDisplay] -> Html
renderReviewCommentsList filesPath reviewComments =
    [hsx|
    <div class="d-flex flex-column gap-3">
        {forEach reviewComments (renderReviewCommentTimelineItem filesPath)}
    </div>
|]

renderReviewCommentTimelineItem :: Text -> PullRequestReviewCommentDisplay -> Html
renderReviewCommentTimelineItem filesPath PullRequestReviewCommentDisplay{pullRequestReviewComment, reviewCommentAuthor, reviewCommentIsOutdated} =
    let location = pullRequestReviewCommentLocation pullRequestReviewComment
        locationHref = filesPath <> "#" <> reviewCommentLineAnchorId location
     in [hsx|
        <div class="border rounded-3 bg-white p-3">
            <div class="d-flex flex-wrap align-items-center gap-2 mb-2">
                <span class="fw-semibold">{get #username reviewCommentAuthor}</span>
                <a
                    class="link-dark small text-decoration-none"
                    href={locationHref}
                    data-posthog-id="pull-request-review-comment-location-link"
                >
                    <code>{pullRequestReviewCommentLocationLabel pullRequestReviewComment}</code>
                </a>
                {renderOutdatedBadge reviewCommentIsOutdated}
            </div>
            {renderPullRequestReviewCommentBody pullRequestReviewComment}
        </div>
    |]

renderOutdatedBadge :: Bool -> Html
renderOutdatedBadge True = [hsx|<span class="badge text-bg-warning">Outdated</span>|]
renderOutdatedBadge False = mempty
