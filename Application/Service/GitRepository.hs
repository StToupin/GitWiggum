module Application.Service.GitRepository
    ( GitHttpRequest (..)
    , GitTreeEntry (..)
    , GitCommitContext (..)
    , GitTreeEntryType (..)
    , cleanupRepositoryOnDisk
    , enableHttpReceivePackOnDisk
    , initializeRepositoryOnDisk
    , listRepositoryBranches
    , listRepositoryTree
    , readLatestCommitContext
    , readRepositoryFile
    , readRepositoryPathType
    , repositoryGitHttpResponse
    , repositoryBarePath
    ) where

import qualified Control.Exception as Exception
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Char8 as ByteString.Char8
import qualified Data.ByteString.Lazy as LazyByteString
import qualified Data.CaseInsensitive as CaseInsensitive
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import qualified Data.Text.Encoding.Error as Text.Encoding.Error
import qualified Data.Text.IO as Text.IO
import IHP.Prelude
import Generated.Types
import qualified Network.HTTP.Types as HTTP
import qualified Network.Wai as WAI
import System.Directory
    ( createDirectoryIfMissing
    , doesPathExist
    , getCurrentDirectory
    , removePathForcibly
    )
import System.Exit (ExitCode (..))
import System.FilePath ((</>), (<.>), takeDirectory)
import System.IO (hClose, hSetBinaryMode)
import System.IO.Temp (withSystemTempDirectory)
import qualified System.Environment as Environment
import System.Process
    ( CreateProcess (cwd, env, std_err, std_in, std_out)
    , StdStream (CreatePipe)
    , proc
    , readCreateProcessWithExitCode
    , waitForProcess
    , withCreateProcess
    )
import Text.Read (readMaybe)

data GitHttpRequest = GitHttpRequest
    { gitPathInfo :: Text
    , queryString :: Text
    , requestMethod :: Text
    , contentType :: Text
    , authType :: Maybe Text
    , remoteUser :: Maybe Text
    , requestBody :: LazyByteString.ByteString
    }
    deriving (Eq, Show)

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
    runGit Nothing ["--git-dir=" <> barePath, "config", "http.receivepack", "true"]

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

enableHttpReceivePackOnDisk :: User -> Repository -> IO ()
enableHttpReceivePackOnDisk owner repository = do
    barePath <- repositoryBarePath owner repository
    _ <- runGit Nothing ["--git-dir=" <> barePath, "config", "http.receivepack", "true"]
    pure ()

repositoryBarePath :: User -> Repository -> IO FilePath
repositoryBarePath owner repository = do
    repoRoot <- getCurrentDirectory
    pure $
        repoRoot
            </> "data"
            </> "repositories"
            </> cs (get #username owner)
            </> (cs (get #name repository) <.> "git")

repositoryGitHttpResponse :: User -> Repository -> GitHttpRequest -> IO (Either Text WAI.Response)
repositoryGitHttpResponse owner repository gitRequest = do
    repoRoot <- getCurrentDirectory
    let projectRoot = repoRoot </> "data" </> "repositories"
    let pathInfo = "/" <> get #username owner <> "/" <> get #name repository <> ".git" <> gitPathInfo gitRequest
    backendResult <- runGitHttpBackend projectRoot pathInfo gitRequest
    pure (parseGitHttpBackendResponse <$> backendResult)

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

runGitHttpBackend :: FilePath -> Text -> GitHttpRequest -> IO (Either Text LazyByteString.ByteString)
runGitHttpBackend projectRoot pathInfo GitHttpRequest { queryString, requestMethod, contentType, authType, remoteUser, requestBody } = do
    baseEnvironment <- Environment.getEnvironment
    let environment =
            mergeEnvironment
                ( [ ("GIT_PROJECT_ROOT", projectRoot)
                  , ("GIT_HTTP_EXPORT_ALL", "1")
                  , ("GATEWAY_INTERFACE", "CGI/1.1")
                  , ("PATH_INFO", cs pathInfo)
                  , ("QUERY_STRING", cs (dropLeadingQuestionMark queryString))
                  , ("REQUEST_METHOD", cs requestMethod)
                  , ("SCRIPT_NAME", "/git")
                  , ("CONTENT_TYPE", cs contentType)
                  , ("CONTENT_LENGTH", cs (tshow (LazyByteString.length requestBody)))
                  ]
                    <> catMaybes
                        [ fmap (\value -> ("AUTH_TYPE", cs value)) authType
                        , fmap (\value -> ("REMOTE_USER", cs value)) remoteUser
                        ]
                )
                baseEnvironment

    let command =
            (proc "git" ["http-backend"])
                { env = Just environment
                , std_in = CreatePipe
                , std_out = CreatePipe
                , std_err = CreatePipe
                }

    withCreateProcess command $ \stdinHandle stdoutHandle stderrHandle processHandle -> do
        let stdin' = fromMaybe (error "Failed to create stdin pipe") stdinHandle
        let stdout' = fromMaybe (error "Failed to create stdout pipe") stdoutHandle
        let stderr' = fromMaybe (error "Failed to create stderr pipe") stderrHandle

        hSetBinaryMode stdin' True
        hSetBinaryMode stdout' True
        hSetBinaryMode stderr' True

        LazyByteString.hPutStr stdin' requestBody
        hClose stdin'

        stdoutBytes <- LazyByteString.hGetContents stdout'
        stderrBytes <- LazyByteString.hGetContents stderr'

        _ <- Exception.evaluate (LazyByteString.length stdoutBytes)
        _ <- Exception.evaluate (LazyByteString.length stderrBytes)

        exitCode <- waitForProcess processHandle

        pure $
            case exitCode of
                ExitSuccess -> Right stdoutBytes
                ExitFailure code ->
                    Left ("git http-backend failed with exit code " <> tshow code <> ": " <> decodeText stderrBytes)

mergeEnvironment :: [(String, String)] -> [(String, String)] -> [(String, String)]
mergeEnvironment overrides baseEnvironment =
    let overriddenKeys = map fst overrides
        filteredBaseEnvironment = filter (\(key, _) -> not (key `elem` overriddenKeys)) baseEnvironment
     in overrides <> filteredBaseEnvironment

parseGitHttpBackendResponse :: LazyByteString.ByteString -> WAI.Response
parseGitHttpBackendResponse output =
    let strictOutput = LazyByteString.toStrict output
        (headerSection, body) = splitHeaders strictOutput
        headerLines =
            headerSection
                |> ByteString.Char8.lines
                |> map (ByteString.Char8.filter (/= '\r'))
                |> filter (not . ByteString.null)
        (status, headers) = parseHeaders headerLines
     in WAI.responseLBS status headers (LazyByteString.fromStrict body)

splitHeaders :: ByteString.ByteString -> (ByteString.ByteString, ByteString.ByteString)
splitHeaders output =
    case ByteString.Char8.breakSubstring "\r\n\r\n" output of
        (headers, rest)
            | not (ByteString.null rest) -> (headers, ByteString.drop 4 rest)
        _ ->
            case ByteString.Char8.breakSubstring "\n\n" output of
                (headers, rest)
                    | not (ByteString.null rest) -> (headers, ByteString.drop 2 rest)
                _ -> (output, "")

parseHeaders :: [ByteString.ByteString] -> (HTTP.Status, HTTP.ResponseHeaders)
parseHeaders headerLines =
    headerLines
        |> foldl' parseHeader (HTTP.status200, [])
        |> second reverse

parseHeader :: (HTTP.Status, HTTP.ResponseHeaders) -> ByteString.ByteString -> (HTTP.Status, HTTP.ResponseHeaders)
parseHeader (currentStatus, currentHeaders) headerLine
    | "Status:" `ByteString.isPrefixOf` headerLine =
        let statusValue = headerLine |> ByteString.drop 7 |> trimByteString
         in (parseStatus statusValue, currentHeaders)
    | otherwise =
        case ByteString.break (== 58) headerLine of
            (headerName, headerValueWithSeparator)
                | ByteString.null headerValueWithSeparator -> (currentStatus, currentHeaders)
                | otherwise ->
                    let headerValue = headerValueWithSeparator |> ByteString.drop 1 |> trimByteString
                     in (currentStatus, (CaseInsensitive.mk headerName, headerValue) : currentHeaders)

parseStatus :: ByteString.ByteString -> HTTP.Status
parseStatus statusValue =
    case ByteString.Char8.words statusValue of
        codeText:messageParts ->
            case readMaybe (cs codeText) of
                Just code -> HTTP.mkStatus code (ByteString.intercalate " " messageParts)
                Nothing -> HTTP.status200
        _ -> HTTP.status200

trimByteString :: ByteString.ByteString -> ByteString.ByteString
trimByteString = ByteString.Char8.dropWhileEnd isSpaceAscii . ByteString.Char8.dropWhile isSpaceAscii

isSpaceAscii :: Char -> Bool
isSpaceAscii = (`elem` [' ', '\t', '\r', '\n'])

dropLeadingQuestionMark :: Text -> Text
dropLeadingQuestionMark queryText =
    if "?" `Text.isPrefixOf` queryText
        then Text.drop 1 queryText
        else queryText

decodeText :: LazyByteString.ByteString -> Text
decodeText = decodeTextStrict . LazyByteString.toStrict

decodeTextStrict :: ByteString.ByteString -> Text
decodeTextStrict = Text.Encoding.decodeUtf8With Text.Encoding.Error.lenientDecode

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
