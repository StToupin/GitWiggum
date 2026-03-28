module Web.View.PullRequests.Conversation where

import Web.View.Prelude
import Web.View.PullRequests.Shell

data ConversationView = ConversationView
    { owner :: User
    , repository :: Repository
    , pullRequest :: PullRequest
    , author :: User
    }

instance View ConversationView where
    html ConversationView { owner, repository, pullRequest, author } =
        renderPullRequestShell owner repository pullRequest author ConversationTab [hsx|
            <div class="card shadow-sm border-0">
                <div class="card-body p-4">
                    <div class="border rounded-3 p-3 bg-light-subtle">
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">Description</div>
                        <div>{fromMaybe ("No description yet." :: Text) (get #description pullRequest)}</div>
                    </div>
                </div>
            </div>
        |]
