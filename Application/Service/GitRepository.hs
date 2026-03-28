module Application.Service.GitRepository
    ( GitTreeEntry (..)
    , GitTreeEntryType (..)
    , cleanupRepositoryOnDisk
    , initializeRepositoryOnDisk
    , listRepositoryTree
    , readRepositoryFile
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

joinTreePath :: Text -> Text -> Text
joinTreePath currentPath entryName =
    if Text.null currentPath
        then entryName
        else currentPath <> "/" <> entryName
