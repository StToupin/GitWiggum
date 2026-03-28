module Application.Service.GitRepository
    ( GitTreeEntry (..)
    , GitCommitContext (..)
    , GitTreeEntryType (..)
    , cleanupRepositoryOnDisk
    , initializeRepositoryOnDisk
    , listRepositoryBranches
    , listRepositoryTree
    , readLatestCommitContext
    , readRepositoryFile
    , readRepositoryPathType
    , repositoryBarePath
    ) where

import qualified Control.Exception as Exception
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import IHP.Prelude
import Generated.Types
import System.Directory
    ( createDirectoryIfMissing
    , doesPathExist
    , getCurrentDirectory
    , removePathForcibly
    )
import System.Exit (ExitCode (..))
import System.FilePath ((</>), (<.>), takeDirectory)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (cwd), proc, readCreateProcessWithExitCode)

data GitTreeEntryType
    = TreeEntryDirectory
    | TreeEntryFile
    deriving (Eq, Show)

data GitTreeEntry = GitTreeEntry
    { entryName :: Text
    , entryPath :: Text
    , entryType :: GitTreeEntryType
    , entryObjectSha :: Text
    }
    deriving (Eq, Show)

data GitCommitContext = GitCommitContext
    { commitSha :: Text
    , commitMessage :: Text
    }
    deriving (Eq, Show)

initializeRepositoryOnDisk :: User -> Repository -> IO Text
initializeRepositoryOnDisk owner repository = do
    barePath <- repositoryBarePath owner repository
    createDirectoryIfMissing True (takeDirectory barePath)

    alreadyExists <- doesPathExist barePath
    when alreadyExists do
        Exception.throwIO (userError ("Repository already exists on disk at " <> barePath))

    runGit Nothing ["init", "--bare", "--initial-branch=" <> cs (get #defaultBranch repository), barePath]

    withSystemTempDirectory "gitwiggum-repository-bootstrap" \tmpDirectory -> do
        let workTreePath = tmpDirectory </> "worktree"
        let defaultBranch = cs (get #defaultBranch repository)

        runGit Nothing ["init", "--initial-branch=" <> defaultBranch, workTreePath]
        Text.IO.writeFile (workTreePath </> "README.md") (initialReadme repository)
        runGit (Just workTreePath) ["config", "user.name", "GitWiggum"]
        runGit (Just workTreePath) ["config", "user.email", "noreply@gitwiggum.local"]
        runGit (Just workTreePath) ["add", "README.md"]
        runGit (Just workTreePath) ["commit", "-m", "Initial commit"]
        runGit (Just workTreePath) ["remote", "add", "origin", barePath]
        runGit (Just workTreePath) ["push", "origin", defaultBranch]
        Text.strip <$> runGit (Just workTreePath) ["rev-parse", "HEAD"]

cleanupRepositoryOnDisk :: User -> Repository -> IO ()
cleanupRepositoryOnDisk owner repository = do
    barePath <- repositoryBarePath owner repository
    pathExists <- doesPathExist barePath
    when pathExists (removePathForcibly barePath)

repositoryBarePath :: User -> Repository -> IO FilePath
repositoryBarePath owner repository = do
    repoRoot <- getCurrentDirectory
    pure $
        repoRoot
            </> "data"
            </> "repositories"
            </> cs (get #username owner)
            </> (cs (get #name repository) <.> "git")

listRepositoryBranches :: User -> Repository -> IO [Text]
listRepositoryBranches owner repository = do
    branches <- readGitOutputMaybe owner repository ["for-each-ref", "--format=%(refname:short)", "refs/heads"]

    pure $
        branches
            |> fromMaybe ""
            |> Text.lines
            |> filter (not . Text.null)
            |> List.sort

listRepositoryTree :: User -> Repository -> Text -> Text -> IO [GitTreeEntry]
listRepositoryTree owner repository branchName currentPath = do
    let treeReference =
            if Text.null currentPath
                then branchName
                else branchName <> ":" <> currentPath

    entries <- readGitOutputMaybe owner repository ["ls-tree", cs treeReference]

    pure $
        entries
            |> fromMaybe ""
            |> Text.lines
            |> mapMaybe (parseTreeEntry currentPath)

readRepositoryFile :: User -> Repository -> Text -> Text -> IO (Maybe Text)
readRepositoryFile owner repository branchName filePath =
    readGitOutputMaybe owner repository ["show", cs (branchName <> ":" <> filePath)]

readRepositoryPathType :: User -> Repository -> Text -> Text -> IO (Maybe GitTreeEntryType)
readRepositoryPathType _ _ _ currentPath | Text.null currentPath = pure (Just TreeEntryDirectory)
readRepositoryPathType owner repository branchName currentPath = do
    objectType <- readGitOutputMaybe owner repository ["cat-file", "-t", cs (branchName <> ":" <> currentPath)]

    pure $
        case objectType >>= parseObjectType . Text.strip of
            Just entryType -> Just entryType
            Nothing -> Nothing

readLatestCommitContext :: User -> Repository -> Text -> Text -> IO (Maybe GitCommitContext)
readLatestCommitContext owner repository branchName filePath = do
    commitDetails <-
        readGitOutputMaybe
            owner
            repository
            ["log", "-1", "--format=%H%x09%s", cs branchName, "--", cs filePath]

    pure $
        commitDetails
            >>= parseCommitContext

initialReadme :: Repository -> Text
initialReadme repository =
    Text.unlines $
        ["# " <> get #name repository]
            <> maybe [] (\description -> ["", description]) (get #description repository)
            <> ["", "Created with GitWiggum."]

readGitOutputMaybe :: User -> Repository -> [String] -> IO (Maybe Text)
readGitOutputMaybe owner repository args = do
    barePath <- repositoryBarePath owner repository
    let command = proc "git" (("--git-dir=" <> barePath) : args)
    (exitCode, stdout, _stderr) <- readCreateProcessWithExitCode command ""

    pure $
        case exitCode of
            ExitSuccess -> Just (cs stdout)
            ExitFailure _ -> Nothing

runGit :: Maybe FilePath -> [String] -> IO Text
runGit workingDirectory args = do
    let command = (proc "git" args) {cwd = workingDirectory}
    (exitCode, stdout, stderr) <- readCreateProcessWithExitCode command ""

    case exitCode of
        ExitSuccess -> pure (cs stdout)
        ExitFailure _ ->
            Exception.throwIO
                (userError ("git " <> List.intercalate " " args <> " failed: " <> stderr))

parseTreeEntry :: Text -> Text -> Maybe GitTreeEntry
parseTreeEntry currentPath line = do
    (metadata, entryName) <- splitTreeLine line
    (_mode, entryType, objectSha) <- parseTreeMetadata metadata

    pure
        GitTreeEntry
            { entryName
            , entryPath = joinTreePath currentPath entryName
            , entryType
            , entryObjectSha = objectSha
            }

splitTreeLine :: Text -> Maybe (Text, Text)
splitTreeLine line =
    case Text.breakOn "\t" line of
        (metadata, entryName)
            | Text.null entryName -> Nothing
            | otherwise -> Just (metadata, Text.drop 1 entryName)

parseTreeMetadata :: Text -> Maybe (Text, GitTreeEntryType, Text)
parseTreeMetadata metadata =
    case Text.words metadata of
        [mode, "tree", objectSha] -> Just (mode, TreeEntryDirectory, objectSha)
        [mode, "blob", objectSha] -> Just (mode, TreeEntryFile, objectSha)
        _ -> Nothing

parseObjectType :: Text -> Maybe GitTreeEntryType
parseObjectType "tree" = Just TreeEntryDirectory
parseObjectType "blob" = Just TreeEntryFile
parseObjectType _ = Nothing

parseCommitContext :: Text -> Maybe GitCommitContext
parseCommitContext line = do
    (sha, message) <- splitTreeLine line
    pure GitCommitContext { commitSha = sha, commitMessage = message }

joinTreePath :: Text -> Text -> Text
joinTreePath currentPath entryName =
    if Text.null currentPath
        then entryName
        else currentPath <> "/" <> entryName
