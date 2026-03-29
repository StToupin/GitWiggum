module Application.Base64 (
    decodeBase64Bytes,
    encodeBase64Bytes,
) where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import qualified Data.ByteString as ByteString
import Data.Char (ord)
import Data.Word (Word8)
import IHP.Prelude

encodeBase64Bytes :: [Word8] -> String
encodeBase64Bytes [] = []
encodeBase64Bytes [byte1] =
    [ base64Alphabet !! fromIntegral (byte1 `shiftR` 2)
    , base64Alphabet !! fromIntegral ((byte1 .&. 0x03) `shiftL` 4)
    , '='
    , '='
    ]
encodeBase64Bytes [byte1, byte2] =
    [ base64Alphabet !! fromIntegral (byte1 `shiftR` 2)
    , base64Alphabet !! fromIntegral (((byte1 .&. 0x03) `shiftL` 4) .|. (byte2 `shiftR` 4))
    , base64Alphabet !! fromIntegral ((byte2 .&. 0x0F) `shiftL` 2)
    , '='
    ]
encodeBase64Bytes (byte1 : byte2 : byte3 : remainingBytes) =
    [ base64Alphabet !! fromIntegral (byte1 `shiftR` 2)
    , base64Alphabet !! fromIntegral (((byte1 .&. 0x03) `shiftL` 4) .|. (byte2 `shiftR` 4))
    , base64Alphabet !! fromIntegral (((byte2 .&. 0x0F) `shiftL` 2) .|. (byte3 `shiftR` 6))
    , base64Alphabet !! fromIntegral (byte3 .&. 0x3F)
    ]
        <> encodeBase64Bytes remainingBytes

decodeBase64Bytes :: String -> Either Text ByteString.ByteString
decodeBase64Bytes encodedBytes
    | length encodedBytes `mod` 4 /= 0 = Left "Invalid base64 length."
    | otherwise = ByteString.pack <$> go encodedBytes
  where
    go [] = Right []
    go (char1 : char2 : char3 : char4 : remainingChars) = do
        decodedChunk <- decodeChunk char1 char2 char3 char4
        (decodedChunk <>) <$> go remainingChars
    go _ =
        Left "Invalid base64 payload."

decodeChunk :: Char -> Char -> Char -> Char -> Either Text [Word8]
decodeChunk char1 char2 '=' '=' = do
    sextet1 <- decodeBase64Char char1
    sextet2 <- decodeBase64Char char2
    pure [fromIntegral ((sextet1 `shiftL` 2) .|. (sextet2 `shiftR` 4))]
decodeChunk char1 char2 char3 '=' = do
    sextet1 <- decodeBase64Char char1
    sextet2 <- decodeBase64Char char2
    sextet3 <- decodeBase64Char char3
    pure
        [ fromIntegral ((sextet1 `shiftL` 2) .|. (sextet2 `shiftR` 4))
        , fromIntegral (((sextet2 .&. 0x0F) `shiftL` 4) .|. (sextet3 `shiftR` 2))
        ]
decodeChunk char1 char2 char3 char4 = do
    sextet1 <- decodeBase64Char char1
    sextet2 <- decodeBase64Char char2
    sextet3 <- decodeBase64Char char3
    sextet4 <- decodeBase64Char char4
    pure
        [ fromIntegral ((sextet1 `shiftL` 2) .|. (sextet2 `shiftR` 4))
        , fromIntegral (((sextet2 .&. 0x0F) `shiftL` 4) .|. (sextet3 `shiftR` 2))
        , fromIntegral (((sextet3 .&. 0x03) `shiftL` 6) .|. sextet4)
        ]

decodeBase64Char :: Char -> Either Text Int
decodeBase64Char character
    | character >= 'A' && character <= 'Z' = Right (ord character - ord 'A')
    | character >= 'a' && character <= 'z' = Right (ord character - ord 'a' + 26)
    | character >= '0' && character <= '9' = Right (ord character - ord '0' + 52)
    | character == '+' = Right 62
    | character == '/' = Right 63
    | otherwise = Left "Invalid base64 payload."

base64Alphabet :: String
base64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
