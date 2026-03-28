module Config where

import IHP.EnvVar
import IHP.Mail.Types
import IHP.Prelude
import IHP.Environment
import IHP.FrameworkConfig
import Network.Socket (PortNumber)

config :: ConfigBuilder
config = do
    smtpHost <- env @Text "SMTP_HOST"
    smtpPort <- env @PortNumber "SMTP_PORT"
    smtpEncryption <- env @SMTPEncryption "SMTP_ENCRYPTION"

    option $
        SMTP
            { host = cs smtpHost
            , port = smtpPort
            , credentials = Nothing
            , encryption = smtpEncryption
            }
