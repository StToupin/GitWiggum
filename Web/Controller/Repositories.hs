module Web.Controller.Repositories where

import Web.Controller.Prelude
import Web.View.Repositories.New

instance Controller RepositoriesController where
    beforeAction = ensureIsUser

    action NewRepositoryAction = render NewView
