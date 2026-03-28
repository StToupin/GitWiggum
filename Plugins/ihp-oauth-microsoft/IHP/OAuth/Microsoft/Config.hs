module IHP.OAuth.Microsoft.Config where

import qualified Control.Monad.Trans.State.Strict as State
import qualified Data.TMap as TMap
import IHP.FrameworkConfig
import IHP.OAuth.Microsoft.Types
import IHP.Prelude
import qualified System.Environment as Env

{- | The Microsoft client id and client secret have to be provided using the
@OAUTH_MICROSOFT_CLIENT_ID@ and @OAUTH_MICROSOFT_CLIENT_SECRET@ env vars.

The optional @OAUTH_MICROSOFT_TENANT_ID@ env var defaults to @common@.

__Example:__ Configure Microsoft OIDC in @Config.hs@

> module Config where
>
> import IHP.Prelude
> import IHP.Environment
> import IHP.FrameworkConfig
> import IHP.OAuth.Microsoft.Config
>
> config :: ConfigBuilder
> config = do
>     option Development
>     option (AppHostname "localhost")
>     initMicrosoftOAuth
-}
initMicrosoftOAuth :: State.StateT TMap.TMap IO ()
initMicrosoftOAuth = do
    clientId <- liftIO $ Env.getEnv "OAUTH_MICROSOFT_CLIENT_ID"
    clientSecret <- liftIO $ Env.getEnv "OAUTH_MICROSOFT_CLIENT_SECRET"
    tenantId <- liftIO $ Env.lookupEnv "OAUTH_MICROSOFT_TENANT_ID"
    option
        MicrosoftOAuthConfig
            { clientId = cs clientId
            , clientSecret = cs clientSecret
            , tenantId = cs (fromMaybe "common" tenantId)
            }

{- | Overrides the default Microsoft OAuth scopes.

Defaults to @["openid", "profile", "email"]@.
-}
setMicrosoftOAuthScope :: [Text] -> State.StateT TMap.TMap IO ()
setMicrosoftOAuthScope scope = option MicrosoftOAuthScopeConfig{scope}
