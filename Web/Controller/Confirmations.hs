module Web.Controller.Confirmations where

import IHP.AuthSupport.Controller.Confirmations (ConfirmationsControllerConfig (..), confirmAction)
import Web.Controller.Prelude

instance ConfirmationsControllerConfig User where
    afterConfirmationRedirectPath = "/Home"

instance Controller ConfirmationsController where
    action ConfirmUserAction { userId, confirmationToken } =
        confirmAction @User userId confirmationToken
