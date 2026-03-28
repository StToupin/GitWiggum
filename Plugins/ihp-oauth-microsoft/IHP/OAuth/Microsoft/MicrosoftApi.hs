module IHP.OAuth.Microsoft.MicrosoftApi where

import Control.Lens hiding (set, (.=), (|>))
import Data.ByteString (ByteString)
import qualified Data.Text as Text
import IHP.ControllerPrelude
import IHP.OAuth.Microsoft.Types
import qualified Network.URI.Encode as URI
import qualified Network.Wreq as Wreq

microsoftConnectUrl :: AuthorizeOptions -> Text
microsoftConnectUrl AuthorizeOptions{..} =
    "https://login.microsoftonline.com/"
        <> URI.encodeText tenantId
        <> "/oauth2/v2.0/authorize"
        <> "?client_id="
        <> URI.encodeText clientId
        <> "&response_type=code"
        <> "&response_mode=query"
        <> "&redirect_uri="
        <> URI.encodeText redirectUri
        <> "&scope="
        <> encodedScope
        <> "&state="
        <> URI.encodeText state
  where
    encodedScope = URI.encodeText (Text.intercalate " " scope)

redirectToMicrosoftConnect :: (?context :: ControllerContext, ?request :: Request) => AuthorizeOptions -> IO ()
redirectToMicrosoftConnect options = do
    redirectToUrl (microsoftConnectUrl options)

tokenEndpoint :: Text -> Text
tokenEndpoint tenantId = "https://login.microsoftonline.com/" <> tenantId <> "/oauth2/v2.0/token"

requestMicrosoftAccessToken :: RequestAccessTokenOptions -> IO AccessTokenResponse
requestMicrosoftAccessToken RequestAccessTokenOptions{..} = do
    let httpOptions =
            Wreq.defaults
                & Wreq.headers
                    .~ [ ("Content-Type", "application/x-www-form-urlencoded")
                       , ("Accept", "application/json")
                       ]
    let payload :: [(ByteString, ByteString)] =
            [ ("client_id", cs clientId)
            , ("client_secret", cs clientSecret)
            , ("grant_type", "authorization_code")
            , ("code", cs code)
            , ("redirect_uri", cs redirectUri)
            ]

    response <- Wreq.asJSON =<< Wreq.postWith httpOptions (cs (tokenEndpoint tenantId)) payload

    pure (response ^. Wreq.responseBody)

requestMicrosoftUser :: Text -> IO MicrosoftUser
requestMicrosoftUser accessToken = do
    let httpOptions =
            Wreq.defaults
                & Wreq.headers
                    .~ [ ("Content-Type", "application/json")
                       , ("Accept", "application/json")
                       , ("Authorization", "Bearer " <> cs accessToken)
                       ]

    response <- Wreq.asJSON =<< Wreq.getWith httpOptions "https://graph.microsoft.com/oidc/userinfo"
    pure (response ^. Wreq.responseBody)

requestMicrosoftGraphMe :: Text -> IO MicrosoftGraphMe
requestMicrosoftGraphMe accessToken = do
    let httpOptions =
            Wreq.defaults
                & Wreq.headers
                    .~ [ ("Content-Type", "application/json")
                       , ("Accept", "application/json")
                       , ("Authorization", "Bearer " <> cs accessToken)
                       ]

    response <- Wreq.asJSON =<< Wreq.getWith httpOptions "https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName"
    pure (response ^. Wreq.responseBody)

-- | Generates and stores OAuth state in the session cookie.
initState :: (?context :: ControllerContext, ?request :: Request) => IO Text
initState = do
    state <- generateAuthenticationToken
    setSession "oauth.microsoft.state" state
    pure state

-- | Verifies the state parameter from the callback.
verifyState :: (?context :: ControllerContext, ?request :: Request) => IO Text
verifyState = do
    let state = param @Text "state"
    expectedState <- fromMaybe (error "state not set") <$> getSession @Text "oauth.microsoft.state"

    accessDeniedUnless (not (isEmpty state))
    accessDeniedUnless (state == expectedState)

    setSession "oauth.microsoft.state" ("" :: Text)

    pure state
