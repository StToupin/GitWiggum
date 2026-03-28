module IHP.OAuth.Microsoft.Types where

import Data.Aeson hiding (Error, Success)
import IHP.Prelude

data MicrosoftOAuthController
    = NewSessionWithMicrosoftAction
    | MicrosoftConnectCallbackAction
    deriving (Eq, Show, Data)

data MicrosoftOAuthConfig = MicrosoftOAuthConfig
    { clientId :: !Text
    , clientSecret :: !Text
    , tenantId :: !Text
    }
    deriving (Eq, Show)

newtype MicrosoftOAuthScopeConfig = MicrosoftOAuthScopeConfig
    { scope :: [Text]
    -- ^ List of scope values, by default should be set to ["openid", "profile", "email"]
    }
    deriving (Eq, Show)

data AuthorizeOptions = AuthorizeOptions
    { clientId :: Text
    -- ^ The client ID for your Microsoft Entra App
    , redirectUri :: Text
    -- ^ The URL in your application where users will be sent after authorization
    , state :: Text
    -- ^ Random string to protect against CSRF attacks
    , scope :: [Text]
    -- ^ OIDC scopes requested from Microsoft
    , tenantId :: Text
    -- ^ Tenant ID, tenant domain or "common"
    }

data RequestAccessTokenOptions = RequestAccessTokenOptions
    { clientId :: Text
    , clientSecret :: Text
    , code :: Text
    , redirectUri :: Text
    , tenantId :: Text
    }

data AccessTokenResponse = AccessTokenResponse
    { accessToken :: Text
    }

data MicrosoftUser = MicrosoftUser
    { sub :: Text
    , email :: Maybe Text
    , emailVerified :: Maybe Bool
    , preferredUsername :: Maybe Text
    , name :: Maybe Text
    , givenName :: Maybe Text
    , familyName :: Maybe Text
    }

data MicrosoftGraphMe = MicrosoftGraphMe
    { mail :: Maybe Text
    , userPrincipalName :: Maybe Text
    }

instance FromJSON AccessTokenResponse where
    parseJSON (Object response) = do
        accessToken <- response .: "access_token"
        pure AccessTokenResponse{..}
    parseJSON _ = fail "Expected a JSON object for AccessTokenResponse"

instance FromJSON MicrosoftUser where
    parseJSON (Object user) = do
        sub <- user .: "sub"
        email <- user .:? "email"
        emailVerified <- user .:? "email_verified"
        preferredUsername <- user .:? "preferred_username"
        name <- user .:? "name"
        givenName <- user .:? "given_name"
        familyName <- user .:? "family_name"
        pure MicrosoftUser{..}
    parseJSON _ = fail "Expected a JSON object for MicrosoftUser"

instance FromJSON MicrosoftGraphMe where
    parseJSON (Object user) = do
        mail <- user .:? "mail"
        userPrincipalName <- user .:? "userPrincipalName"
        pure MicrosoftGraphMe{..}
    parseJSON _ = fail "Expected a JSON object for MicrosoftGraphMe"
