{-# LANGUAGE AllowAmbiguousTypes #-}

module IHP.OAuth.Microsoft.Controller where

import qualified Control.Exception as Exception
import qualified Data.Char as Char
import qualified Data.TMap as TMap
import qualified Data.Text as Text
import Hasql.Implicits.Encoders (DefaultParamEncoder)
import qualified IHP.AuthSupport.Controller.Sessions as Sessions
import qualified IHP.AuthSupport.Lockable as Lockable
import IHP.ControllerPrelude
import IHP.Hasql.FromRow (FromRowHasql)
import IHP.LoginSupport.Types
import qualified IHP.OAuth.Microsoft.MicrosoftApi as Microsoft
import qualified IHP.OAuth.Microsoft.Types as Microsoft

newSessionWithMicrosoftAction ::
    forall user.
    ( ?context :: ControllerContext
    , ?request :: Request
    , AutoRoute Microsoft.MicrosoftOAuthController
    ) =>
    IO ()
newSessionWithMicrosoftAction = do
    state <- Microsoft.initState
    let options =
            Microsoft.AuthorizeOptions
                { clientId = microsoftOAuthConfig.clientId
                , redirectUri = urlTo Microsoft.MicrosoftConnectCallbackAction
                , state
                , scope = microsoftOAuthScopeConfig.scope
                , tenantId = microsoftOAuthConfig.tenantId
                }
    Microsoft.redirectToMicrosoftConnect options

microsoftConnectCallbackAction ::
    forall user emailField.
    ( MicrosoftOAuthControllerConfig user
    , HasField "email" user emailField
    , SetField "email" user emailField
    , DefaultParamEncoder emailField
    , OAuthEmailField emailField
    , EqOrIsOperator emailField
    , user ~ GetModelByTableName (GetTableName user)
    , FromRowHasql user
    , ?modelContext :: ModelContext
    , KnownSymbol (GetTableName user)
    , HasField "microsoftUserId" user (Maybe Text)
    , AutoRoute Microsoft.MicrosoftOAuthController
    , HasNewSessionUrl user
    , Typeable user
    , ?context :: ControllerContext
    , ?request :: Request
    , HasField "id" user (Id user)
    , CanUpdate user
    , SetField "failedLoginAttempts" user Int
    , KnownSymbol (GetModelName user)
    , Show (PrimaryKey (GetTableName user))
    , HasField "lockedAt" user (Maybe UTCTime)
    , Sessions.SessionsControllerConfig user
    , SetField "microsoftUserId" user (Maybe Text)
    , SetField "passwordHash" user Text
    , Record user
    , CanCreate user
    , Table user
    ) =>
    IO ()
microsoftConnectCallbackAction = do
    handleMicrosoftCallbackError @user

    let code = param @Text "code"
    _ <- Microsoft.verifyState

    let redirectUri = urlTo Microsoft.MicrosoftConnectCallbackAction
    accessTokenResponse <-
        Microsoft.requestMicrosoftAccessToken
            Microsoft.RequestAccessTokenOptions
                { clientId = microsoftOAuthConfig.clientId
                , clientSecret = microsoftOAuthConfig.clientSecret
                , code
                , redirectUri
                , tenantId = microsoftOAuthConfig.tenantId
                }

    let accessToken = accessTokenResponse.accessToken
    let ?accessToken = accessToken
    microsoftUser <- Microsoft.requestMicrosoftUser accessToken
    graphMe <- Exception.try (Microsoft.requestMicrosoftGraphMe accessToken)

    maybeUser :: Maybe user <-
        query @user
            |> filterWhere (#microsoftUserId, Just microsoftUser.sub)
            |> fetchOneOrNothing

    case maybeUser of
        Just user -> do
            ensureIsNotLocked user
            Sessions.beforeLogin user
            beforeLogin user microsoftUser >>= setAndPersistLoginSuccess
            pure ()
        Nothing -> do
            let maybeEmail :: Maybe Text = resolveMicrosoftEmail microsoftUser <|> resolveMicrosoftGraphEmail graphMe
            let resolvedEmail :: Text = fromMaybe (fallbackMicrosoftEmail microsoftUser) maybeEmail

            when (isNothing maybeEmail) do
                putStrLn "Microsoft OAuth: no email claim from userinfo or /me, using deterministic placeholder email."

            when (microsoftUser.emailVerified == Just False && isJust maybeEmail) do
                setErrorMessage "Your Microsoft account email needs to be verified before you can sign in."
                redirectToPath (newSessionUrl (Proxy @user))

            userWithSameEmail :: Maybe user <-
                query @user
                    |> filterWhere (#email, oauthEmailFieldFromText resolvedEmail)
                    |> fetchOneOrNothing

            case userWithSameEmail of
                Just existingUser -> do
                    ensureIsNotLocked existingUser
                    Sessions.beforeLogin existingUser
                    existingUser
                        |> set #microsoftUserId (Just microsoftUser.sub)
                        |> (\updatedUser -> beforeLogin updatedUser microsoftUser)
                        >>= setAndPersistLoginSuccess
                    pure ()
                Nothing -> do
                    randomPassword <- generateAuthenticationToken
                    hashed <- hashPassword randomPassword

                    let newUser =
                            newRecord @user
                                |> set #passwordHash hashed
                                |> set #email (oauthEmailFieldFromText resolvedEmail)
                                |> set #microsoftUserId (Just microsoftUser.sub)

                    newUser <- createUser (beforeCreateUser newUser microsoftUser) microsoftUser
                    afterCreateUser newUser
                    login newUser

    redirectUrl <- getSessionAndClear "IHP.LoginSupport.redirectAfterLogin"
    redirectToPath (fromMaybe (Sessions.afterLoginRedirectPath @user) redirectUrl)

{- | See Microsoft OAuth error response docs:
https://learn.microsoft.com/entra/identity-platform/v2-oauth2-auth-code-flow
-}
handleMicrosoftCallbackError ::
    forall user.
    ( HasNewSessionUrl user
    , ?context :: ControllerContext
    , ?request :: Request
    ) =>
    IO ()
handleMicrosoftCallbackError = do
    let errorType = paramOrNothing @Text "error"
    let redirectToLoginPage = redirectToPath (newSessionUrl (Proxy @user))

    case errorType of
        Just "access_denied" -> redirectToLoginPage
        Just otherError -> do
            setErrorMessage (paramOrDefault otherError "error_description")
            redirectToLoginPage
        Nothing -> pure ()

resolveMicrosoftEmail :: Microsoft.MicrosoftUser -> Maybe Text
resolveMicrosoftEmail microsoftUser =
    case microsoftUser.email of
        Just email -> Just email
        Nothing -> microsoftUser.preferredUsername

resolveMicrosoftGraphEmail :: Either Exception.SomeException Microsoft.MicrosoftGraphMe -> Maybe Text
resolveMicrosoftGraphEmail (Left _) = Nothing
resolveMicrosoftGraphEmail (Right graphMe) =
    case graphMe.mail of
        Just mail -> Just mail
        Nothing -> graphMe.userPrincipalName

fallbackMicrosoftEmail :: Microsoft.MicrosoftUser -> Text
fallbackMicrosoftEmail microsoftUser =
    let normalizedSub = Text.toLower (Text.take 96 (Text.filter isSafeMicrosoftEmailChar microsoftUser.sub))
        localPart = if Text.null normalizedSub then "microsoft-user" else "microsoft-" <> normalizedSub
     in localPart <> "@oauth.microsoft.local"

isSafeMicrosoftEmailChar :: Char -> Bool
isSafeMicrosoftEmailChar char =
    Char.isAlphaNum char || char == '.' || char == '_' || char == '-'

setAndPersistLoginSuccess ::
    forall user.
    ( CanUpdate user
    , SetField "failedLoginAttempts" user Int
    , KnownSymbol (GetModelName user)
    , HasField "id" user (Id user)
    , Show (PrimaryKey (GetTableName user))
    , ?modelContext :: ModelContext
    , ?request :: Request
    ) =>
    user -> IO user
setAndPersistLoginSuccess user = do
    user <-
        user
            |> set #failedLoginAttempts 0
            |> updateRecord
    login user
    pure user

class MicrosoftOAuthControllerConfig user where
    createUser :: (?context :: ControllerContext, ?modelContext :: ModelContext, CanCreate user, ?accessToken :: Text) => user -> Microsoft.MicrosoftUser -> IO user
    createUser user _microsoftUser = createRecord user

    beforeCreateUser :: (?context :: ControllerContext, ?modelContext :: ModelContext, CanCreate user, ?accessToken :: Text) => user -> Microsoft.MicrosoftUser -> user
    beforeCreateUser user _microsoftUser = user

    afterCreateUser :: (?context :: ControllerContext, ?modelContext :: ModelContext, CanCreate user, ?accessToken :: Text) => user -> IO ()
    afterCreateUser _user = pure ()

    beforeLogin :: (?context :: ControllerContext, ?modelContext :: ModelContext, CanUpdate user, ?accessToken :: Text) => user -> Microsoft.MicrosoftUser -> IO user
    beforeLogin user _microsoftUser = pure user

class OAuthEmailField emailField where
    oauthEmailFieldFromText :: Text -> emailField

instance OAuthEmailField Text where
    oauthEmailFieldFromText email = email

instance OAuthEmailField (Maybe Text) where
    oauthEmailFieldFromText email = Just email

microsoftOAuthConfig :: (?context :: ControllerContext) => Microsoft.MicrosoftOAuthConfig
microsoftOAuthConfig =
    ?context.frameworkConfig.appConfig
        |> TMap.lookup @Microsoft.MicrosoftOAuthConfig
        |> fromMaybe (error "Could not find MicrosoftOAuthConfig in config. Did you forget to call 'initMicrosoftOAuth' inside your Config.hs?")

microsoftOAuthScopeConfig :: (?context :: ControllerContext) => Microsoft.MicrosoftOAuthScopeConfig
microsoftOAuthScopeConfig =
    ?context.frameworkConfig.appConfig
        |> TMap.lookup @Microsoft.MicrosoftOAuthScopeConfig
        |> fromMaybe Microsoft.MicrosoftOAuthScopeConfig{scope = ["openid", "profile", "email", "User.Read"]}

ensureIsNotLocked ::
    forall user.
    ( ?context :: ControllerContext
    , ?request :: Request
    , HasNewSessionUrl user
    , HasField "lockedAt" user (Maybe UTCTime)
    ) =>
    user -> IO ()
ensureIsNotLocked user = do
    isLocked <- Lockable.isLocked user
    when isLocked do
        setErrorMessage "User is locked"
        redirectToPath (newSessionUrl (Proxy @user))
