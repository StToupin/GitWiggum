module Web.Worker where

import Application.Job.DiffAiResponseJob ()
import Generated.Types
import IHP.Job.Runner
import IHP.Job.Types
import IHP.Prelude
import Web.Types

instance Worker WebApplication where
    workers _ =
        [ worker @DiffAiResponseJob
        ]
