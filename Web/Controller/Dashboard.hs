module Web.Controller.Dashboard where

import Web.Controller.Prelude
import Web.View.Dashboard.Index

instance Controller DashboardController where
    beforeAction = ensureIsUser

    action DashboardAction = do
        repositories <-
            query @Repository
                |> filterWhere (#ownerUserId, get #id currentUser)
                |> orderByDesc #createdAt
                |> fetch

        render IndexView { repositories }
