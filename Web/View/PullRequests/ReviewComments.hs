module Web.View.PullRequests.ReviewComments (
    PullRequestReviewCommentDisplay (..),
    ReviewCommentLocation (..),
    ReviewCommentComposer (..),
    ReviewCommentComposerSlotView (..),
    blankReviewCommentComposer,
    pullRequestReviewCommentLocation,
    pullRequestReviewCommentLocationLabel,
    renderPullRequestReviewCommentBody,
    renderReviewCommentComposerDetails,
    reviewCommentComposerSlotId,
    reviewCommentLineAnchorId,
    reviewCommentLocationKey,
) where

import qualified Data.Char as Char
import qualified Data.Text as Text
import Web.View.Prelude

data PullRequestReviewCommentDisplay = PullRequestReviewCommentDisplay
    { pullRequestReviewComment :: PullRequestReviewComment
    , reviewCommentAuthor :: User
    , reviewCommentIsOutdated :: Bool
    }

data ReviewCommentLocation = ReviewCommentLocation
    { reviewCommentFilePath :: Text
    , reviewCommentSide :: Text
    , reviewCommentLineNumber :: Int
    }
    deriving (Eq, Show)

data ReviewCommentComposer = ReviewCommentComposer
    { reviewCommentLocation :: ReviewCommentLocation
    , reviewCommentBody :: Text
    , reviewCommentBodyError :: Maybe Text
    }

data ReviewCommentComposerSlotView = ReviewCommentComposerSlotView
    { commentPath :: Text
    , composer :: ReviewCommentComposer
    }

instance View ReviewCommentComposerSlotView where
    html ReviewCommentComposerSlotView{commentPath, composer} =
        renderReviewCommentComposerSlot commentPath composer

blankReviewCommentComposer :: ReviewCommentLocation -> ReviewCommentComposer
blankReviewCommentComposer reviewCommentLocation =
    ReviewCommentComposer
        { reviewCommentLocation
        , reviewCommentBody = ""
        , reviewCommentBodyError = Nothing
        }

pullRequestReviewCommentLocation :: PullRequestReviewComment -> ReviewCommentLocation
pullRequestReviewCommentLocation pullRequestReviewComment =
    ReviewCommentLocation
        { reviewCommentFilePath = get #filePath pullRequestReviewComment
        , reviewCommentSide = get #side pullRequestReviewComment
        , reviewCommentLineNumber = get #lineNumber pullRequestReviewComment
        }

pullRequestReviewCommentLocationLabel :: PullRequestReviewComment -> Text
pullRequestReviewCommentLocationLabel =
    reviewCommentLocationLabel . pullRequestReviewCommentLocation

renderPullRequestReviewCommentBody :: PullRequestReviewComment -> Html
renderPullRequestReviewCommentBody pullRequestReviewComment =
    [hsx|
    <pre class="mb-0 bg-transparent border-0 p-0 text-wrap">{get #body pullRequestReviewComment}</pre>
|]

renderReviewCommentComposerDetails :: Text -> ReviewCommentComposer -> Html
renderReviewCommentComposerDetails commentPath composer =
    [hsx|
    <details class="d-inline-block">
        <summary
            class="btn btn-outline-dark btn-sm"
            style="list-style: none;"
            data-posthog-id="pull-request-diff-review-comment-toggle"
        >
            Comment
        </summary>
        {renderReviewCommentComposerSlot commentPath composer}
    </details>
|]

renderReviewCommentComposerSlot :: Text -> ReviewCommentComposer -> Html
renderReviewCommentComposerSlot commentPath composer =
    let location = reviewCommentLocation composer
        slotId = reviewCommentComposerSlotId location
        textAreaId = slotId <> "-body"
     in [hsx|
        <div id={slotId} class="mt-2">
            <form class="border rounded-3 bg-white p-3" hx-post={commentPath} hx-target={"#" <> slotId} hx-select={"#" <> slotId} hx-swap="outerHTML">
                <input type="hidden" name="filePath" value={reviewCommentFilePath location}/>
                <input type="hidden" name="side" value={reviewCommentSide location}/>
                <input type="hidden" name="lineNumber" value={tshow (reviewCommentLineNumber location)}/>
                <div class="mb-2">
                    <label class="form-label small fw-semibold text-secondary mb-1" for={textAreaId}>
                        Add comment
                    </label>
                    <textarea
                        id={textAreaId}
                        name="body"
                        rows="3"
                        class={reviewCommentTextAreaClass (isJust (reviewCommentBodyError composer))}
                        placeholder="Share feedback on this line"
                    >{reviewCommentBody composer}</textarea>
                    {reviewCommentValidationFeedback (reviewCommentBodyError composer)}
                </div>
                <div class="d-flex justify-content-end">
                    <button class="btn btn-dark btn-sm" type="submit" data-posthog-id="pull-request-diff-review-comment-submit">
                        Add comment
                    </button>
                </div>
            </form>
        </div>
    |]

reviewCommentTextAreaClass :: Bool -> Text
reviewCommentTextAreaClass hasError =
    if hasError
        then "form-control is-invalid"
        else "form-control"

reviewCommentValidationFeedback :: Maybe Text -> Html
reviewCommentValidationFeedback Nothing = mempty
reviewCommentValidationFeedback (Just errorText) =
    [hsx|
    <div class="invalid-feedback d-block">{errorText}</div>
|]

reviewCommentLocationLabel :: ReviewCommentLocation -> Text
reviewCommentLocationLabel location =
    reviewCommentFilePath location
        <> ":"
        <> tshow (reviewCommentLineNumber location)
        <> " ("
        <> reviewCommentSideLabel (reviewCommentSide location)
        <> ")"

reviewCommentSideLabel :: Text -> Text
reviewCommentSideLabel "old" = "old"
reviewCommentSideLabel "new" = "new"
reviewCommentSideLabel side = side

reviewCommentComposerSlotId :: ReviewCommentLocation -> Text
reviewCommentComposerSlotId location =
    "pull-request-review-comment-composer-" <> reviewCommentLocationKey location

reviewCommentLineAnchorId :: ReviewCommentLocation -> Text
reviewCommentLineAnchorId location =
    "pull-request-review-comment-line-" <> reviewCommentLocationKey location

reviewCommentLocationKey :: ReviewCommentLocation -> Text
reviewCommentLocationKey location =
    sanitizeDomIdPart $
        reviewCommentFilePath location
            <> "-"
            <> reviewCommentSide location
            <> "-"
            <> tshow (reviewCommentLineNumber location)

sanitizeDomIdPart :: Text -> Text
sanitizeDomIdPart =
    Text.map (\char -> if Char.isAlphaNum char then char else '-')
