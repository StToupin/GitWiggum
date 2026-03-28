module Web.View.PullRequests.New where

import qualified Data.Text as Text
import IHP.ValidationSupport.Types (getValidationFailure)
import Web.View.Prelude
import Web.View.Repositories.Shell

data NewView = NewView
    { owner :: User
    , repository :: Repository
    , pullRequest :: PullRequest
    , availableBranches :: [Text]
    }

instance View NewView where
    html NewView { owner, repository, pullRequest, availableBranches } =
        let ownerSlug = get #username owner
            repositoryName = get #name repository
            pullRequestsPath =
                pathTo
                    RepositoryPullRequestsAction
                        { ownerSlug = ownerSlug
                        , repositoryName = repositoryName
                        }
            createPullRequestPath =
                pathTo
                    CreatePullRequestAction
                        { ownerSlug = ownerSlug
                        , repositoryName = repositoryName
                        }
         in
            renderRepositoryShell owner repository PullRequestsTab [hsx|
                <div class="row justify-content-center">
                    <div class="col-12 col-xl-10">
                        <div class="card shadow-sm border-0">
                            <div class="card-body p-4 p-lg-5">
                                <div class="d-flex flex-column flex-lg-row align-items-lg-center justify-content-between gap-3 mb-4">
                                    <div>
                                        <div class="text-uppercase small fw-semibold text-secondary mb-2">Pull requests</div>
                                        <h2 class="h4 mb-1">Open a pull request</h2>
                                        <p class="text-secondary mb-0">
                                            Choose a base branch and compare branch, then create a stable review route.
                                        </p>
                                    </div>
                                    <a
                                        class="btn btn-outline-dark"
                                        href={pullRequestsPath}
                                        data-posthog-id="pull-request-new-back"
                                    >
                                        Back to pull requests
                                    </a>
                                </div>

                                <form
                                    method="POST"
                                    action={createPullRequestPath}
                                    class="d-grid gap-4"
                                >
                                    <div>
                                        <label class="form-label" for="pull-request-title">Title</label>
                                        <input
                                            class={inputClass (isJust (getValidationFailure #title pullRequest))}
                                            id="pull-request-title"
                                            type="text"
                                            name="title"
                                            value={get #title pullRequest}
                                            autocomplete="off"
                                            required="required"
                                            data-posthog-id="pull-request-title"
                                        />
                                        {validationFeedback (getValidationFailure #title pullRequest)}
                                    </div>

                                    <div>
                                        <label class="form-label" for="pull-request-description">Description</label>
                                        <textarea
                                            class="form-control"
                                            id="pull-request-description"
                                            name="description"
                                            rows="5"
                                            data-posthog-id="pull-request-description"
                                        >{fromMaybe "" (get #description pullRequest)}</textarea>
                                    </div>

                                    <div class="row g-3">
                                        <div class="col-12 col-lg-6">
                                            <label class="form-label" for="pull-request-base-branch">Base branch</label>
                                            <select
                                                class={inputClass (isJust (getValidationFailure #baseBranch pullRequest))}
                                                id="pull-request-base-branch"
                                                name="baseBranch"
                                                data-posthog-id="pull-request-base-branch"
                                            >
                                                {forEach availableBranches (renderBranchOption (get #baseBranch pullRequest))}
                                            </select>
                                            {validationFeedback (getValidationFailure #baseBranch pullRequest)}
                                        </div>
                                        <div class="col-12 col-lg-6">
                                            <label class="form-label" for="pull-request-compare-branch">Compare branch</label>
                                            <select
                                                class={inputClass (isJust (getValidationFailure #compareBranch pullRequest))}
                                                id="pull-request-compare-branch"
                                                name="compareBranch"
                                                data-posthog-id="pull-request-compare-branch"
                                            >
                                                <option value="" selected={Text.null (get #compareBranch pullRequest)}>Select a compare branch</option>
                                                {forEach availableBranches (renderBranchOption (get #compareBranch pullRequest))}
                                            </select>
                                            <div class="form-text">
                                                Push a branch first if the branch you need is not listed yet.
                                            </div>
                                            {validationFeedback (getValidationFailure #compareBranch pullRequest)}
                                        </div>
                                    </div>

                                    <div class="form-check">
                                        <input
                                            class="form-check-input"
                                            type="checkbox"
                                            value="on"
                                            id="pull-request-is-draft"
                                            name="isDraft"
                                            checked={get #isDraft pullRequest}
                                            data-posthog-id="pull-request-is-draft"
                                        />
                                        <label class="form-check-label" for="pull-request-is-draft">
                                            Create as draft
                                        </label>
                                    </div>

                                    <div class="d-flex flex-wrap gap-2">
                                        <button class="btn btn-dark" type="submit" data-posthog-id="pull-request-create-submit">
                                            Create pull request
                                        </button>
                                        <a
                                            class="btn btn-outline-dark"
                                            href={pullRequestsPath}
                                            data-posthog-id="pull-request-create-cancel"
                                        >
                                            Cancel
                                        </a>
                                    </div>
                                </form>
                            </div>
                        </div>
                    </div>
                </div>
            |]

renderBranchOption :: Text -> Text -> Html
renderBranchOption selectedBranch branchName =
    [hsx|<option value={branchName} selected={branchName == selectedBranch}>{branchName}</option>|]

inputClass :: Bool -> Text
inputClass hasError =
    "form-control" <> if hasError then " is-invalid" else ""

validationFeedback :: Maybe Text -> Html
validationFeedback (Just text) = [hsx|<div class="invalid-feedback d-block">{text}</div>|]
validationFeedback Nothing = mempty
