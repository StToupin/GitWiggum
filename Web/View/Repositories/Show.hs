module Web.View.Repositories.Show where

import qualified Data.Text as Text
import Web.View.Prelude
import Web.View.Repositories.Shell

data ShowView = ShowView
    { owner :: User
    , repository :: Repository
    , readmeContent :: Maybe Text
    , rootEntries :: [Text]
    }

instance View ShowView where
    html ShowView { owner, repository, readmeContent, rootEntries } =
        renderRepositoryShell owner repository BrowserTab [hsx|
                <div class="card shadow-sm border-0 mb-4">
                    <div class="card-body p-4">
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">Browser</div>
                        <h2 class="h5 mb-1">Repository root</h2>
                        <p class="text-secondary mb-0">
                            This canonical route now carries repository context and the default branch bootstrap content.
                        </p>
                    </div>
                </div>

                <div class="row g-4 mb-4">
                    <div class="col-12 col-md-6 col-xl-3">
                        <div class="card shadow-sm border-0 h-100">
                            <div class="card-body p-4">
                                <div class="text-uppercase small fw-semibold text-secondary mb-2">Selected branch</div>
                                <div class="fs-4 fw-semibold">{get #defaultBranch repository}</div>
                            </div>
                        </div>
                    </div>
                    <div class="col-12 col-md-6 col-xl-3">
                        <div class="card shadow-sm border-0 h-100">
                            <div class="card-body p-4">
                                <div class="text-uppercase small fw-semibold text-secondary mb-2">Current path</div>
                                <div class="fs-5 fw-semibold"><code>{currentPathLabel}</code></div>
                            </div>
                        </div>
                    </div>
                    <div class="col-12 col-md-6 col-xl-3">
                        <div class="card shadow-sm border-0 h-100">
                            <div class="card-body p-4">
                                <div class="text-uppercase small fw-semibold text-secondary mb-2">Latest commit</div>
                                <div class="fs-5 fw-semibold"><code>{latestCommitLabel repository}</code></div>
                            </div>
                        </div>
                    </div>
                    <div class="col-12 col-md-6 col-xl-3">
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
        |]

latestCommitLabel :: Repository -> Text
latestCommitLabel repository =
    repository
        |> get #latestCommitSha
        |> fromMaybe "Pending"
        |> Text.take 10

currentPathLabel :: Text
currentPathLabel = "/"

renderRootEntry :: Text -> Html
renderRootEntry entry = [hsx|<span class="badge text-bg-light">{entry}</span>|]
