module Web.View.PullRequests.Files where

import qualified Application.Service.DiffAI as DiffAI
import Application.Service.GitRepository
import qualified Data.Char as Char
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import IHP.Job.Types (JobStatus (..))
import Web.View.Prelude
import Web.View.PullRequests.ReviewComments
import Web.View.PullRequests.Shell

data FilesView = FilesView
    { owner :: User
    , repository :: Repository
    , pullRequest :: PullRequest
    , author :: User
    , diffFiles :: [GitDiffFile]
    , reviewComments :: [PullRequestReviewCommentDisplay]
    , diffAiJobs :: [DiffAiResponseJob]
    , headSha :: Maybe Text
    }

data DiffAiResponseRowView = DiffAiResponseRowView
    {diffAiResponseJob :: DiffAiResponseJob}

instance View FilesView where
    html FilesView{owner, repository, pullRequest, author, diffFiles, reviewComments, diffAiJobs, headSha} =
        let ownerSlug = get #username owner
            repositoryName = get #name repository
            reviewCommentPath =
                pathTo
                    CreatePullRequestReviewCommentAction
                        { ownerSlug
                        , repositoryName
                        , pullRequestNumber = get #number pullRequest
                        }
            askAiPath =
                pathTo
                    CreatePullRequestDiffAiJobAction
                        { ownerSlug
                        , repositoryName
                        , pullRequestNumber = get #number pullRequest
                        }
            jobsByFingerprint =
                diffAiJobs
                    |> map (\diffAiResponseJob -> (get #fingerprint diffAiResponseJob, diffAiResponseJob))
                    |> Map.fromList
            reviewCommentsByLocation =
                reviewComments
                    |> map
                        ( \pullRequestReviewCommentDisplay ->
                            ( reviewCommentLocationKey (pullRequestReviewCommentLocation (pullRequestReviewComment pullRequestReviewCommentDisplay))
                            , [pullRequestReviewCommentDisplay]
                            )
                        )
                    |> Map.fromListWith (flip (<>))
         in renderPullRequestShell
                owner
                repository
                pullRequest
                author
                FilesTab
                [hsx|
            <div class="d-flex flex-column gap-4">
                {if null diffFiles then emptyFilesState else forEach diffFiles (renderDiffFile reviewCommentPath askAiPath pullRequest headSha reviewCommentsByLocation jobsByFingerprint)}
            </div>
        |]

instance View DiffAiResponseRowView where
    html DiffAiResponseRowView{diffAiResponseJob} =
        renderDiffAiResponseSwapTable (renderDiffAiResponseRow diffAiResponseJob)

emptyFilesState :: Html
emptyFilesState =
    [hsx|
    <div class="card shadow-sm border-0">
        <div class="card-body p-4">
            <div class="text-uppercase small fw-semibold text-secondary mb-2">Files</div>
            <p class="mb-0 text-secondary">No changes are in this compare range.</p>
        </div>
    </div>
|]

renderDiffFile :: Text -> Text -> PullRequest -> Maybe Text -> Map.Map Text [PullRequestReviewCommentDisplay] -> Map.Map Text DiffAiResponseJob -> GitDiffFile -> Html
renderDiffFile reviewCommentPath askAiPath pullRequest headSha reviewCommentsByLocation jobsByFingerprint diffFile@GitDiffFile{hunks} =
    let diffFilePath = diffFileRequestPath diffFile
     in [hsx|
    <div class="card shadow-sm border-0">
        <div class="card-body p-4">
            <div class="d-flex flex-wrap align-items-center justify-content-between gap-3 mb-3">
                <div>
                    <div class="text-uppercase small fw-semibold text-secondary mb-2">Changed file</div>
                    <h3 class="h6 mb-0"><code>{diffFileLabel diffFile}</code></h3>
                </div>
                <span class="badge text-bg-light">{tshow (length hunks)} hunks</span>
            </div>

            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <tbody>
                        {forEach hunks (renderDiffHunk reviewCommentPath askAiPath pullRequest headSha reviewCommentsByLocation jobsByFingerprint diffFilePath)}
                    </tbody>
                </table>
            </div>
        </div>
    </div>
|]

renderDiffHunk :: Text -> Text -> PullRequest -> Maybe Text -> Map.Map Text [PullRequestReviewCommentDisplay] -> Map.Map Text DiffAiResponseJob -> Text -> GitDiffHunk -> Html
renderDiffHunk reviewCommentPath askAiPath pullRequest headSha reviewCommentsByLocation jobsByFingerprint diffFilePath GitDiffHunk{header, lines} =
    [hsx|
    <hsx-fragment>
        <tr class="table-light">
            <td class="text-secondary text-end small"><code>-</code></td>
            <td class="text-secondary text-end small"><code>-</code></td>
            <td class="font-monospace small"><code>{header}</code></td>
        </tr>
        {forEach lines (renderDiffLine reviewCommentPath askAiPath pullRequest headSha reviewCommentsByLocation jobsByFingerprint diffFilePath)}
    </hsx-fragment>
|]

renderDiffLine :: Text -> Text -> PullRequest -> Maybe Text -> Map.Map Text [PullRequestReviewCommentDisplay] -> Map.Map Text DiffAiResponseJob -> Text -> GitDiffLine -> Html
renderDiffLine reviewCommentPath askAiPath pullRequest headSha reviewCommentsByLocation jobsByFingerprint diffFilePath diffLine@GitDiffLine{lineType, content, oldLineNumber, newLineNumber} =
    let maybeReviewCommentLocation = diffReviewCommentLocation diffFilePath diffLine
        lineAnchorId = maybe "" reviewCommentLineAnchorId maybeReviewCommentLocation
        reviewCommentsForLine =
            maybe
                []
                (\location -> Map.findWithDefault [] (reviewCommentLocationKey location) reviewCommentsByLocation)
                maybeReviewCommentLocation
        maybeDiffAiLocation = diffAiLocation diffFilePath diffLine
        maybeFingerprint =
            case (headSha, maybeDiffAiLocation) of
                (Just currentHeadSha, Just location) ->
                    Just (DiffAI.buildDiffAiFingerprint pullRequest currentHeadSha location)
                _ ->
                    Nothing
        maybeSlotId =
            maybeFingerprint
                >>= (\fingerprint -> Just (diffAiSlotId fingerprint))
        maybeDiffAiJob =
            maybeFingerprint
                >>= (\fingerprint -> Map.lookup fingerprint jobsByFingerprint)
     in [hsx|
        <hsx-fragment>
            <tr id={lineAnchorId} class={diffLineRowClass lineType}>
                <td class="text-secondary text-end small align-top"><code>{renderLineNumber oldLineNumber}</code></td>
                <td class="text-secondary text-end small align-top"><code>{renderLineNumber newLineNumber}</code></td>
                <td class="font-monospace align-top">
                    <div class="d-flex flex-wrap align-items-start justify-content-between gap-3">
                        <pre class="mb-0 bg-transparent border-0 p-0 flex-grow-1"><code>{diffLinePrefix lineType}{content}</code></pre>
                        <div class="d-flex flex-wrap align-items-start justify-content-end gap-2">
                            {maybe mempty (renderReviewCommentComposerDetails reviewCommentPath . blankReviewCommentComposer) maybeReviewCommentLocation}
                            {renderAskAiAction askAiPath maybeSlotId maybeDiffAiLocation}
                        </div>
                    </div>
                </td>
            </tr>
            {renderReviewCommentsRow reviewCommentsForLine}
            {renderDiffAiResponseSlotRow maybeSlotId maybeDiffAiJob}
        </hsx-fragment>
    |]

renderReviewCommentsRow :: [PullRequestReviewCommentDisplay] -> Html
renderReviewCommentsRow [] = mempty
renderReviewCommentsRow reviewComments =
    [hsx|
    <tr class="table-light">
        <td></td>
        <td></td>
        <td>
            <div class="d-flex flex-column gap-2 my-2">
                {forEach reviewComments renderInlineReviewComment}
            </div>
        </td>
    </tr>
|]

renderInlineReviewComment :: PullRequestReviewCommentDisplay -> Html
renderInlineReviewComment PullRequestReviewCommentDisplay{pullRequestReviewComment, reviewCommentAuthor} =
    [hsx|
    <div class="border rounded-3 bg-white p-3">
        <div class="d-flex flex-wrap align-items-center gap-2 mb-2">
            <span class="fw-semibold small">{get #username reviewCommentAuthor}</span>
            <span class="badge text-bg-light">
                <code>{pullRequestReviewCommentLocationLabel pullRequestReviewComment}</code>
            </span>
        </div>
        {renderPullRequestReviewCommentBody pullRequestReviewComment}
    </div>
|]

renderAskAiAction :: Text -> Maybe Text -> Maybe DiffAI.DiffAiLocation -> Html
renderAskAiAction _ _ Nothing = mempty
renderAskAiAction _ Nothing _ = mempty
renderAskAiAction askAiPath (Just slotId) (Just location) =
    [hsx|
    <form
        class="d-inline-flex"
        hx-post={askAiPath}
        hx-target={"#" <> slotId}
        hx-select={"#" <> slotId}
        hx-swap="outerHTML"
    >
        <input type="hidden" name="filePath" value={location.filePath}/>
        <input type="hidden" name="side" value={location.side}/>
        <input type="hidden" name="lineNumber" value={tshow location.lineNumber}/>
        <button class="btn btn-outline-dark btn-sm" type="submit" data-posthog-id="pull-request-diff-ask-ai">
            Ask AI
        </button>
    </form>
|]

renderDiffAiResponseSlotRow :: Maybe Text -> Maybe DiffAiResponseJob -> Html
renderDiffAiResponseSlotRow Nothing _ = mempty
renderDiffAiResponseSlotRow (Just slotId) maybeDiffAiJob =
    case maybeDiffAiJob of
        Just diffAiResponseJob ->
            renderDiffAiResponseRow diffAiResponseJob
        Nothing ->
            renderDiffAiResponseSlotPlaceholder slotId

renderDiffAiResponseSlotPlaceholder :: Text -> Html
renderDiffAiResponseSlotPlaceholder slotId =
    [hsx|
    <tr id={slotId} class="d-none" data-diff-ai-response-slot="true">
        <td colspan="3" class="p-0 border-0"></td>
    </tr>
|]

renderDiffAiResponseSwapTable :: Html -> Html
renderDiffAiResponseSwapTable rowHtml =
    [hsx|
    <table class="d-none">
        <tbody>{rowHtml}</tbody>
    </table>
|]

renderDiffAiResponseRow :: DiffAiResponseJob -> Html
renderDiffAiResponseRow diffAiResponseJob =
    let slotId = diffAiSlotId (get #fingerprint diffAiResponseJob)
     in [hsx|
        <tr id={slotId} class="table-light" data-diff-ai-response-slot="true">
            <td></td>
            <td></td>
            <td>
                <div class="border rounded-3 bg-white p-3 my-2">
                    <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-2">
                        <div class="text-uppercase small fw-semibold text-secondary">AI explanation</div>
                        <span class={diffAiStatusBadgeClass (get #status diffAiResponseJob)}>
                            {diffAiStatusLabel (get #status diffAiResponseJob)}
                        </span>
                    </div>
                    {renderDiffAiResponseBody diffAiResponseJob}
                </div>
            </td>
        </tr>
    |]

renderDiffAiResponseBody :: DiffAiResponseJob -> Html
renderDiffAiResponseBody diffAiResponseJob =
    case get #status diffAiResponseJob of
        JobStatusNotStarted ->
            [hsx|
            <div class="text-secondary">Queued. The explanation job has been created.</div>
        |]
        JobStatusRunning ->
            [hsx|
            <div class="d-flex flex-column gap-2">
                <div class="text-secondary">Generating explanation...</div>
                {renderDiffAiResponseText diffAiResponseJob}
            </div>
        |]
        JobStatusRetry ->
            [hsx|
            <div class="d-flex flex-column gap-2">
                <div class="text-secondary">Retrying explanation...</div>
                {renderDiffAiResponseText diffAiResponseJob}
            </div>
        |]
        JobStatusFailed ->
            [hsx|
            <div class="text-danger">{fromMaybe ("The explanation job failed." :: Text) (get #lastError diffAiResponseJob)}</div>
        |]
        JobStatusTimedOut ->
            [hsx|
            <div class="text-danger">{fromMaybe ("The explanation job timed out." :: Text) (get #lastError diffAiResponseJob)}</div>
        |]
        JobStatusSucceeded ->
            renderDiffAiResponseText diffAiResponseJob

renderDiffAiResponseText :: DiffAiResponseJob -> Html
renderDiffAiResponseText diffAiResponseJob =
    [hsx|
    <pre class="mb-0 bg-transparent border-0 p-0 text-wrap"><code>{fromMaybe ("" :: Text) (get #response diffAiResponseJob)}</code></pre>
|]

diffFileLabel :: GitDiffFile -> Text
diffFileLabel GitDiffFile{oldPath, newPath}
    | Text.null oldPath = newPath
    | Text.null newPath = oldPath <> " (deleted)"
    | oldPath == newPath = newPath
    | otherwise = oldPath <> " -> " <> newPath

diffFileRequestPath :: GitDiffFile -> Text
diffFileRequestPath GitDiffFile{oldPath, newPath}
    | Text.null newPath = oldPath
    | otherwise = newPath

diffLinePrefix :: GitDiffLineType -> Text
diffLinePrefix DiffContextLine = " "
diffLinePrefix DiffAdditionLine = "+"
diffLinePrefix DiffDeletionLine = "-"

diffLineRowClass :: GitDiffLineType -> Text
diffLineRowClass DiffContextLine = ""
diffLineRowClass DiffAdditionLine = "table-success"
diffLineRowClass DiffDeletionLine = "table-danger"

diffAiLocation :: Text -> GitDiffLine -> Maybe DiffAI.DiffAiLocation
diffAiLocation filePath GitDiffLine{lineType, oldLineNumber, newLineNumber} =
    case lineType of
        DiffAdditionLine ->
            newLineNumber
                >>= (\lineNumber -> Just DiffAI.DiffAiLocation{filePath, side = DiffAI.diffAiSideNew, lineNumber})
        DiffDeletionLine ->
            oldLineNumber
                >>= (\lineNumber -> Just DiffAI.DiffAiLocation{filePath, side = DiffAI.diffAiSideOld, lineNumber})
        DiffContextLine ->
            Nothing

diffReviewCommentLocation :: Text -> GitDiffLine -> Maybe ReviewCommentLocation
diffReviewCommentLocation filePath GitDiffLine{lineType, oldLineNumber, newLineNumber} =
    case lineType of
        DiffAdditionLine ->
            newLineNumber
                >>= (\lineNumber -> Just ReviewCommentLocation{reviewCommentFilePath = filePath, reviewCommentSide = "new", reviewCommentLineNumber = lineNumber})
        DiffDeletionLine ->
            oldLineNumber
                >>= (\lineNumber -> Just ReviewCommentLocation{reviewCommentFilePath = filePath, reviewCommentSide = "old", reviewCommentLineNumber = lineNumber})
        DiffContextLine ->
            case newLineNumber <|> oldLineNumber of
                Just lineNumber ->
                    Just
                        ReviewCommentLocation
                            { reviewCommentFilePath = filePath
                            , reviewCommentSide = if isJust newLineNumber then "new" else "old"
                            , reviewCommentLineNumber = lineNumber
                            }
                Nothing ->
                    Nothing

diffAiStatusLabel :: JobStatus -> Text
diffAiStatusLabel JobStatusNotStarted = "Queued"
diffAiStatusLabel JobStatusRunning = "Running"
diffAiStatusLabel JobStatusRetry = "Retrying"
diffAiStatusLabel JobStatusFailed = "Failed"
diffAiStatusLabel JobStatusTimedOut = "Timed out"
diffAiStatusLabel JobStatusSucceeded = "Ready"

diffAiStatusBadgeClass :: JobStatus -> Text
diffAiStatusBadgeClass JobStatusNotStarted = "badge text-bg-secondary"
diffAiStatusBadgeClass JobStatusRunning = "badge text-bg-primary"
diffAiStatusBadgeClass JobStatusRetry = "badge text-bg-warning"
diffAiStatusBadgeClass JobStatusFailed = "badge text-bg-danger"
diffAiStatusBadgeClass JobStatusTimedOut = "badge text-bg-danger"
diffAiStatusBadgeClass JobStatusSucceeded = "badge text-bg-success"

diffAiSlotId :: Text -> Text
diffAiSlotId fingerprint =
    "diff-ai-response-slot-" <> sanitizeDomIdPart fingerprint

sanitizeDomIdPart :: Text -> Text
sanitizeDomIdPart =
    Text.map (\char -> if Char.isAlphaNum char then char else '-')

renderLineNumber :: Maybe Int -> Text
renderLineNumber =
    maybe "" tshow
