module Web.View.Repositories.New where

import IHP.ValidationSupport.Types (getValidationFailure)
import Web.View.Prelude

data NewView = NewView { repository :: Repository }

instance View NewView where
    html NewView { repository } = [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-lg-8 col-xl-7">
                <div class="card shadow-sm border-0">
                    <div class="card-body p-4 p-lg-5">
                        <div class="mb-4">
                            <div class="text-uppercase small fw-semibold text-secondary mb-2">Repositories</div>
                            <h1 class="h2 mb-2">Create repository</h1>
                            <p class="text-secondary mb-0">
                                New repositories will live under
                                <code class="ms-1">{ownerNamespacePath currentUser}</code>.
                            </p>
                        </div>

                        <form method="POST" action={pathTo CreateRepositoryAction} class="d-grid gap-4">
                            <div>
                                <label class="form-label" for="repository-name">Repository name</label>
                                <input
                                    class={inputClass (isJust (getValidationFailure #name repository))}
                                    id="repository-name"
                                    type="text"
                                    name="name"
                                    value={get #name repository}
                                    autocomplete="off"
                                    required="required"
                                />
                                <div class="form-text">Use a slug-friendly name with letters, numbers, underscores, or hyphens.</div>
                                {validationFeedback (getValidationFailure #name repository)}
                            </div>

                            <div>
                                <label class="form-label" for="repository-description">Description</label>
                                <textarea
                                    class="form-control"
                                    id="repository-description"
                                    name="description"
                                    rows="3"
                                >{fromMaybe "" (get #description repository)}</textarea>
                            </div>

                            <div>
                                <div class="form-label mb-2">Visibility</div>
                                <div class="d-grid gap-2">
                                    <label class="border rounded-3 p-3 d-flex justify-content-between align-items-center">
                                        <span>
                                            <span class="fw-semibold d-block">Public</span>
                                            <span class="text-secondary small">Visible to anyone who can reach this host.</span>
                                        </span>
                                        <input
                                            type="radio"
                                            name="visibility"
                                            value="public"
                                            checked={not (get #isPrivate repository)}
                                            data-posthog-id="repository-visibility-public"
                                        />
                                    </label>
                                    <label class="border rounded-3 p-3 d-flex justify-content-between align-items-center">
                                        <span>
                                            <span class="fw-semibold d-block">Private</span>
                                            <span class="text-secondary small">Restricted to you until sharing lands.</span>
                                        </span>
                                        <input
                                            type="radio"
                                            name="visibility"
                                            value="private"
                                            checked={get #isPrivate repository}
                                            data-posthog-id="repository-visibility-private"
                                        />
                                    </label>
                                </div>
                            </div>

                            <div class="d-flex flex-wrap gap-2">
                                <button class="btn btn-dark" type="submit" data-posthog-id="repository-create-submit">
                                    Create repository
                                </button>
                                <a class="btn btn-outline-dark" href={pathTo DashboardAction} data-posthog-id="repository-new-back-dashboard">
                                    Cancel
                                </a>
                            </div>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    |]

inputClass :: Bool -> Text
inputClass hasError =
    "form-control" <> if hasError then " is-invalid" else ""

validationFeedback :: Maybe Text -> Html
validationFeedback (Just text) = [hsx|<div class="invalid-feedback d-block">{text}</div>|]
validationFeedback Nothing = mempty
