module Application.Service.SshKeys
    ( isLikelySshPublicKey
    , normalizeSshPublicKey
    ) where

import qualified Data.Char as Char
import qualified Data.Text as Text
import IHP.Prelude

normalizeSshPublicKey :: Text -> Either Text (Maybe Text)
normalizeSshPublicKey raw =
    let keyLines =
            raw
                |> Text.lines
                |> map Text.strip
                |> filter (not . Text.null)
     in case keyLines of
            [] -> Right Nothing
            [publicKey]
                | isLikelySshPublicKey publicKey -> Right (Just publicKey)
                | otherwise -> Left "Paste a single SSH public key."
            _ -> Left "Paste a single SSH public key."

isLikelySshPublicKey :: Text -> Bool
isLikelySshPublicKey publicKey =
    case Text.words publicKey of
        algorithm:keyMaterial:_ ->
            algorithm `elem` supportedAlgorithms
                && not (Text.null keyMaterial)
                && Text.all isBase64KeyChar keyMaterial
        _ -> False

supportedAlgorithms :: [Text]
supportedAlgorithms =
    [ "ecdsa-sha2-nistp256"
    , "ecdsa-sha2-nistp384"
    , "ecdsa-sha2-nistp521"
    , "sk-ecdsa-sha2-nistp256@openssh.com"
    , "sk-ssh-ed25519@openssh.com"
    , "ssh-dss"
    , "ssh-ed25519"
    , "ssh-rsa"
    ]

isBase64KeyChar :: Char -> Bool
isBase64KeyChar char =
    Char.isAsciiUpper char
        || Char.isAsciiLower char
        || Char.isDigit char
        || char `elem` ['+', '/', '=']
