module Application.Helper.Owner where

import IHP.Prelude
import Generated.Types

personalOwnerSlug :: User -> Text
personalOwnerSlug user = get #username user

ownerNamespacePath :: User -> Text
ownerNamespacePath user = "/" <> personalOwnerSlug user
