module Application.Service.GitHttpAuth (
    GitHttpAccessLevel (..),
    GitHttpPrincipal (..),
    authenticateGitHttpPrincipal,
    gitHttpAccessLevel,
    parseBasicAuthorizationHeader,
) where

import Application.Base64 (decodeBase64Bytes)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Char8 as ByteString.Char8
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import qualified Data.Text.Encoding.Error as Text.Encoding.Error
import Generated.Types
import IHP.AuthSupport.Authentication (verifyPassword)
import IHP.ControllerPrelude (fetchOneOrNothing, query)
import IHP.Prelude
import IHP.QueryBuilder (filterWhereCaseInsensitive)
import qualified Network.HTTP.Types.Header as HTTPHeader
import qualified Network.Wai as WAI

data GitHttpAccessLevel
    = GitReadAccess
    | GitWriteAccess
    deriving (Eq, Show)

data GitHttpPrincipal = GitHttpPrincipal
    { user :: User
    , remoteUser :: Text
    }
    deriving (Eq, Show)

gitHttpAccessLevel :: Text -> Text -> GitHttpAccessLevel
gitHttpAccessLevel rawQueryString gitPathInfo =
    if "service=git-receive-pack" `Text.isInfixOf` rawQueryString || "/git-receive-pack" `Text.isSuffixOf` gitPathInfo
        then GitWriteAccess
        else GitReadAccess

parseBasicAuthorizationHeader :: Maybe ByteString.ByteString -> Maybe (Text, Text)
parseBasicAuthorizationHeader authorizationHeader = do
    rawValue <- authorizationHeader
    encodedCredentials <- ByteString.stripPrefix "Basic " rawValue
    decodedCredentials <- either (const Nothing) Just (decodeBase64Bytes (ByteString.Char8.unpack encodedCredentials))
    let credentialsText = Text.Encoding.decodeUtf8With Text.Encoding.Error.lenientDecode decodedCredentials
    let (loginName, passwordWithSeparator) = Text.breakOn ":" credentialsText
    password <- Text.stripPrefix ":" passwordWithSeparator
    let normalizedLoginName = Text.strip loginName
    if Text.null normalizedLoginName
        then Nothing
        else pure (normalizedLoginName, password)

authenticateGitHttpPrincipal ::
    (?modelContext :: ModelContext) =>
    WAI.Request ->
    IO (Maybe GitHttpPrincipal)
authenticateGitHttpPrincipal request =
    case parseBasicAuthorizationHeader (lookup HTTPHeader.hAuthorization request.requestHeaders) of
        Nothing ->
            pure Nothing
        Just (loginName, password) -> do
            maybeUser <- lookupUserByGitHttpLogin loginName
            pure $
                case maybeUser of
                    Just foundUser
                        | foundUser.isConfirmed && verifyPassword foundUser password ->
                            Just
                                GitHttpPrincipal
                                    { user = foundUser
                                    , remoteUser = preferredRemoteUser foundUser
                                    }
                    _ -> Nothing

lookupUserByGitHttpLogin :: (?modelContext :: ModelContext) => Text -> IO (Maybe User)
lookupUserByGitHttpLogin rawLoginName = do
    let loginName = Text.strip rawLoginName
    if Text.null loginName
        then pure Nothing
        else
            if "@" `Text.isInfixOf` loginName
                then lookupUserByEmail loginName
                else do
                    userByUsername <- lookupUserByUsername loginName
                    case userByUsername of
                        Just user -> pure (Just user)
                        Nothing -> lookupUserByEmail loginName

lookupUserByEmail :: (?modelContext :: ModelContext) => Text -> IO (Maybe User)
lookupUserByEmail emailAddress =
    query @User
        |> filterWhereCaseInsensitive (#email, emailAddress)
        |> fetchOneOrNothing

lookupUserByUsername :: (?modelContext :: ModelContext) => Text -> IO (Maybe User)
lookupUserByUsername username =
    query @User
        |> filterWhereCaseInsensitive (#username, username)
        |> fetchOneOrNothing

preferredRemoteUser :: User -> Text
preferredRemoteUser foundUser =
    case nonEmptyText foundUser.username of
        Just username -> username
        Nothing -> foundUser.email

nonEmptyText :: Text -> Maybe Text
nonEmptyText rawText =
    let strippedText = Text.strip rawText
     in if Text.null strippedText then Nothing else Just strippedText
