module Web.View.Repositories.Show where

import qualified Data.Text as Text
import Web.View.Prelude

data ShowView = ShowView
    { owner :: User
    , repository :: Repository
    , readmeContent :: Maybe Text
    , rootEntries :: [Text]
    }

instance View ShowView where
    html ShowView { owner, repository, readmeContent, rootEntries } = [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-xl-8">
                <div class="d-flex flex-column flex-lg-row align-items-lg-center justify-content-between gap-3 mb-4">
                    <div>
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">Repository</div>
                        <h1 class="h2 mb-1">{get #username owner}/{get #name repository}</h1>
                        <p class="text-secondary mb-0">{fromMaybe "No description yet." (get #description repository)}</p>
                    </div>
                    <div class="d-flex flex-wrap gap-2">
                        <span class="badge text-bg-light align-self-start">{visibilityLabel repository}</span>
                        <a class="btn btn-outline-dark" href={pathTo DashboardAction} data-posthog-id="repository-show-dashboard">
                            Back to dashboard
                        </a>
                    </div>
                </div>

                <div class="row g-4 mb-4">
                    <div class="col-12 col-md-4">
                        <div class="card shadow-sm border-0 h-100">
                            <div class="card-body p-4">
                                <div class="text-uppercase small fw-semibold text-secondary mb-2">Default branch</div>
                                <div class="fs-4 fw-semibold">{get #defaultBranch repository}</div>
                            </div>
                        </div>
                    </div>
                    <div class="col-12 col-md-4">
                        <div class="card shadow-sm border-0 h-100">
                            <div class="card-body p-4">
                                <div class="text-uppercase small fw-semibold text-secondary mb-2">Latest commit</div>
                                <div class="fs-5 fw-semibold"><code>{latestCommitLabel repository}</code></div>
                            </div>
                        </div>
                    </div>
                    <div class="col-12 col-md-4">
                        <div class="card shadow-sm border-0 h-100">
                            <div class="card-body p-4">
                                <div class="text-uppercase small fw-semibold text-secondary mb-2">Root entries</div>
                                <div class="d-flex flex-wrap gap-2">
                                    {forEach rootEntries renderRootEntry}
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="card shadow-sm border-0">
                    <div class="card-body p-4">
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">README.md</div>
                        <pre class="bg-body-tertiary rounded-3 p-3 mb-0"><code>{fromMaybe "README.md is not available yet." readmeContent}</code></pre>
                    </div>
                </div>
            </div>
        </div>
    |]

latestCommitLabel :: Repository -> Text
latestCommitLabel repository =
    repository
        |> get #latestCommitSha
        |> fromMaybe "Pending"
        |> Text.take 10

renderRootEntry :: Text -> Html
renderRootEntry entry = [hsx|<span class="badge text-bg-light">{entry}</span>|]

visibilityLabel :: Repository -> Text
visibilityLabel repository =
    if get #isPrivate repository then "Private" else "Public"
