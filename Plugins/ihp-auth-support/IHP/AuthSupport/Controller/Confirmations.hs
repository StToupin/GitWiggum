{-# LANGUAGE AllowAmbiguousTypes #-}

module IHP.AuthSupport.Controller.Confirmations (
    confirmAction,
    ConfirmationsControllerConfig (..),
) where

import qualified Hasql.Mapping as Mapping
import IHP.ControllerPrelude hiding (setErrorMessage, setSuccessMessage)
import IHP.FlashMessages (setErrorMessage, setSuccessMessage)
import IHP.Hasql.FromRow (FromRowHasql)
import Network.Wai (Request)

class ConfirmationsControllerConfig user where
    afterConfirmationRedirectPath :: Text
    afterConfirmationRedirectPath = "/NewSession"

    confirmationSuccessMessage :: Text
    confirmationSuccessMessage = "Your account has been confirmed"

    confirmationInvalidMessage :: Text
    confirmationInvalidMessage = "Invalid confirmation link"

    confirmationAlreadyConfirmedMessage :: Text
    confirmationAlreadyConfirmedMessage = "Your account is already confirmed"

    afterConfirmation :: (?context :: ControllerContext, ?modelContext :: ModelContext) => user -> IO ()
    afterConfirmation _ = pure ()

confirmAction ::
    forall user.
    ( ?context :: ControllerContext
    , ?modelContext :: ModelContext
    , ?request :: Request
    , Table user
    , user ~ GetModelByTableName (GetTableName user)
    , FilterPrimaryKey (GetTableName user)
    , Mapping.IsScalar (PrimaryKey (GetTableName user))
    , FromRowHasql user
    , CanUpdate user
    , ConfirmationsControllerConfig user
    , HasField "id" user (Id user)
    , Show (PrimaryKey (GetTableName user))
    , HasField "confirmationToken" user (Maybe Text)
    , HasField "isConfirmed" user Bool
    , SetField "confirmationToken" user (Maybe Text)
    , SetField "isConfirmed" user Bool
    ) =>
    Id user -> Text -> IO ()
confirmAction userId token = do
    user <- fetchOneOrNothing userId
    case user of
        Nothing -> do
            setErrorMessage (confirmationInvalidMessage @user)
            redirectToPath (afterConfirmationRedirectPath @user)
        Just user ->
            if get #isConfirmed user
                then do
                    setSuccessMessage (confirmationAlreadyConfirmedMessage @user)
                    redirectToPath (afterConfirmationRedirectPath @user)
                else case get #confirmationToken user of
                    Just storedToken | storedToken == token -> do
                        updatedUser <-
                            user
                                |> set #isConfirmed True
                                |> set #confirmationToken (Nothing :: Maybe Text)
                                |> updateRecord
                        afterConfirmation updatedUser
                        setSuccessMessage (confirmationSuccessMessage @user)
                        redirectToPath (afterConfirmationRedirectPath @user)
                    _ -> do
                        setErrorMessage (confirmationInvalidMessage @user)
                        redirectToPath (afterConfirmationRedirectPath @user)
