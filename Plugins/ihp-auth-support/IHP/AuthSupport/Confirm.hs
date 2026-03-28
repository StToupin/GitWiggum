{-# LANGUAGE AllowAmbiguousTypes #-}

module IHP.AuthSupport.Confirm (
    ConfirmationMail (..),
    sendConfirmationMail,
    ensureIsConfirmed,
) where

import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDV4
import IHP.ControllerPrelude hiding (setErrorMessage)
import IHP.FlashMessages (setErrorMessage)
import IHP.MailPrelude (BuildMail, sendMail)
import Network.Wai (Request)

-- | Mail payload for email confirmations.
data ConfirmationMail user = ConfirmationMail
    { user :: user
    , confirmationToken :: Text
    }

sendConfirmationMail ::
    ( ?context :: ControllerContext
    , ?modelContext :: ModelContext
    , SetField "confirmationToken" user (Maybe Text)
    , CanUpdate user
    , BuildMail (ConfirmationMail user)
    ) =>
    user -> IO ()
sendConfirmationMail user = do
    token <- UUID.toText <$> UUIDV4.nextRandom
    updatedUser <-
        user
            |> set #confirmationToken (Just token)
            |> updateRecord
    sendMail (ConfirmationMail updatedUser token)

ensureIsConfirmed ::
    ( ?context :: ControllerContext
    , ?request :: Request
    , HasField "isConfirmed" user Bool
    ) =>
    user -> IO ()
ensureIsConfirmed user =
    unless (get #isConfirmed user) do
        setErrorMessage "Please confirm your email before logging in"
        redirectToPath "/"
