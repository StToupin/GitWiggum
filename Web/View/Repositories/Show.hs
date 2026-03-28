module Web.View.Repositories.Show where

import Application.Service.GitRepository
import qualified Data.Text as Text
import Web.View.Prelude
import Web.View.Repositories.Shell

data ShowView = ShowView
    { owner :: User
    , repository :: Repository
    , branchName :: Text
    , currentPath :: Text
    , availableBranches :: [Text]
    , treeEntries :: [GitTreeEntry]
    , readmeContent :: Maybe Text
    }

instance View ShowView where
    html ShowView { owner, repository, branchName, currentPath, availableBranches, treeEntries, readmeContent } =
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
                    <div class="col-12 col-md-4">
                        <div class="card shadow-sm border-0 h-100">
                            <div class="card-body p-4">
                                <div class="text-uppercase small fw-semibold text-secondary mb-2">Selected branch</div>
                                <div class="fs-4 fw-semibold">{branchName}</div>
                            </div>
                        </div>
                    </div>
                    <div class="col-12 col-md-4">
                        <div class="card shadow-sm border-0 h-100">
                            <div class="card-body p-4">
                                <div class="text-uppercase small fw-semibold text-secondary mb-2">Current path</div>
                                <div class="fs-5 fw-semibold"><code>{currentPathLabel currentPath}</code></div>
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
                </div>

                <div class="card shadow-sm border-0 mb-4">
                    <div class="card-body p-4">
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">Branch selector</div>
                        <div class="d-flex flex-wrap gap-2">
                            {forEach availableBranches (renderBranchSelector owner repository currentPath branchName)}
                        </div>
                    </div>
                </div>

                <div class="card shadow-sm border-0 mb-4">
                    <div class="card-body p-4">
                        <div class="d-flex flex-wrap align-items-center justify-content-between gap-3 mb-3">
                            <div>
                                <div class="text-uppercase small fw-semibold text-secondary mb-2">Directory explorer</div>
                                <h2 class="h5 mb-0">{currentPathLabel currentPath}</h2>
                            </div>
                            <span class="badge text-bg-light">{tshow (length treeEntries)} entries</span>
                        </div>

                        <div class="d-grid gap-2">
                            {if null treeEntries then emptyDirectoryState else forEach treeEntries (renderTreeEntry owner repository branchName)}
                        </div>
                    </div>
                </div>

                {renderReadmePreview readmeContent}
        |]

currentPathLabel :: Text -> Text
currentPathLabel currentPath =
    if Text.null currentPath then "/" else "/" <> currentPath

renderReadmePreview :: Maybe Text -> Html
renderReadmePreview Nothing = mempty
renderReadmePreview (Just readmeContent) = [hsx|
                <div class="card shadow-sm border-0">
                    <div class="card-body p-4">
                        <div class="text-uppercase small fw-semibold text-secondary mb-2">README.md</div>
                        <pre class="bg-body-tertiary rounded-3 p-3 mb-0"><code>{readmeContent}</code></pre>
                    </div>
                </div>
|]

latestCommitLabel :: Repository -> Text
latestCommitLabel repository =
    repository
        |> get #latestCommitSha
        |> fromMaybe "Pending"
        |> Text.take 10

emptyDirectoryState :: Html
emptyDirectoryState = [hsx|
    <div class="border rounded-3 p-3 text-secondary">
        This directory is empty.
    </div>
|]

renderBranchSelector :: User -> Repository -> Text -> Text -> Text -> Html
renderBranchSelector owner repository currentPath selectedBranch targetBranch =
    let branchPath =
            if targetBranch == get #defaultBranch repository && Text.null currentPath
                then pathTo
                    ShowRepositoryAction
                        { ownerSlug = get #username owner
                        , repositoryName = get #name repository
                        }
                else pathTo
                    RepositoryTreeAction
                        { ownerSlug = get #username owner
                        , repositoryName = get #name repository
                        , branchName = targetBranch
                        , treePath = currentPath
                        }
     in [hsx|
        <a
            class={branchSelectorClass selectedBranch targetBranch}
            href={branchPath}
            data-posthog-id="repository-browser-branch"
        >
            {targetBranch}
        </a>
    |]

branchSelectorClass :: Text -> Text -> Text
branchSelectorClass selectedBranch targetBranch =
    if selectedBranch == targetBranch
        then "btn btn-dark"
        else "btn btn-outline-dark"

renderTreeEntry :: User -> Repository -> Text -> GitTreeEntry -> Html
renderTreeEntry owner repository branchName GitTreeEntry { entryName, entryPath, entryType } =
    let folderPath =
            pathTo
                RepositoryTreeAction
                    { ownerSlug = get #username owner
                    , repositoryName = get #name repository
                    , branchName
                    , treePath = entryPath
                    }
     in case entryType of
            TreeEntryDirectory -> [hsx|
                <a
                    class="border rounded-3 p-3 d-flex align-items-center justify-content-between gap-3 text-decoration-none"
                    href={folderPath}
                    data-posthog-id="repository-browser-folder"
                >
                    <span class="fw-semibold">{entryName}</span>
                    <span class="badge text-bg-light">Folder</span>
                </a>
            |]
            TreeEntryFile -> [hsx|
                <div class="border rounded-3 p-3 d-flex align-items-center justify-content-between gap-3">
                    <span class="fw-semibold">{entryName}</span>
                    <span class="badge text-bg-light">File</span>
                </div>
            |]
