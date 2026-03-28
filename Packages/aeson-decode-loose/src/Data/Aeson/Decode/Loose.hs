module Data.Aeson.Decode.Loose (decodeLoose, repairJsonText) where

import qualified Data.Aeson as Aeson
import Data.Char (isSpace)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

decodeLoose :: T.Text -> Either String Aeson.Value
decodeLoose input =
    case Aeson.eitherDecodeStrict' (TE.encodeUtf8 input) of
        Right value -> Right value
        Left _ -> Aeson.eitherDecodeStrict' (TE.encodeUtf8 (repairJsonText input))

repairJsonText :: T.Text -> T.Text
repairJsonText input =
    let t0 = T.stripEnd input
        (endedInString0, _) = scanJson t0
        t1 = if endedInString0 then closeString t0 else t0
        t2 = insertNullForDanglingKeysNoColon t1
        t3 = insertNullBeforeClosers t2
        t3a = completeBareLiterals t3
        t4 = stripTrailingCommas t3a
        (inStr, stack) = scanJson t4
        t5 = if inStr then closeString t4 else t4
        closers = T.pack (map closingFor stack)
        t6 = T.append t5 closers
        t7 = insertNullBeforeClosers t6
        t8 = stripTrailingCommas t7
     in t8

closingFor :: Char -> Char
closingFor '{' = '}'
closingFor '[' = ']'
closingFor c = c

scanJson :: T.Text -> (Bool, [Char])
scanJson t = go False False [] (T.unpack t)
  where
    go :: Bool -> Bool -> [Char] -> String -> (Bool, [Char])
    go inStr _ stk [] = (inStr, stk)
    go inStr esc stk (c : cs)
        | inStr =
            if esc
                then go True False stk cs
                else case c of
                    '\\' -> go True True stk cs
                    '"' -> go False False stk cs
                    _ -> go True False stk cs
        | otherwise =
            case c of
                '"' -> go True False stk cs
                '{' -> go False False ('{' : stk) cs
                '}' -> go False False (pop '{' stk) cs
                '[' -> go False False ('[' : stk) cs
                ']' -> go False False (pop '[' stk) cs
                _ -> go False False stk cs

    pop :: Char -> [Char] -> [Char]
    pop expected (x : xs) | x == expected = xs
    pop _ xs = xs

closeString :: T.Text -> T.Text
closeString t =
    let endsWithBackslash = not (T.null t) && T.last t == '\\'
     in if endsWithBackslash
            then T.snoc (T.snoc t '\\') '"'
            else T.snoc t '"'

stripTrailingCommas :: T.Text -> T.Text
stripTrailingCommas t = T.pack (go (T.unpack t) False False)
  where
    go :: String -> Bool -> Bool -> String
    go [] _ _ = []
    go (c : cs) inStr esc
        | inStr =
            if esc
                then c : go cs True False
                else case c of
                    '\\' -> c : go cs True True
                    '"' -> c : go cs False False
                    _ -> c : go cs True False
        | c == '"' = c : go cs True False
        | c == ',' =
            case dropWhile isSpace cs of
                ('}' : _) -> go cs False False
                (']' : _) -> go cs False False
                _ -> c : go cs False False
        | otherwise = c : go cs False False

insertNullBeforeClosers :: T.Text -> T.Text
insertNullBeforeClosers t = T.pack (go (T.unpack t) False False)
  where
    go :: String -> Bool -> Bool -> String
    go [] _ _ = []
    go (c : cs) inStr esc
        | inStr =
            if esc
                then c : go cs True False
                else case c of
                    '\\' -> c : go cs True True
                    '"' -> c : go cs False False
                    _ -> c : go cs True False
        | c == '"' = c : go cs True False
        | c == ':' =
            case dropWhile isSpace cs of
                [] -> c : ' ' : 'n' : 'u' : 'l' : 'l' : go cs False False
                ('}' : _) -> c : ' ' : 'n' : 'u' : 'l' : 'l' : go cs False False
                (']' : _) -> c : ' ' : 'n' : 'u' : 'l' : 'l' : ' ' : '}' : go cs False False
                _ -> c : go cs False False
        | otherwise = c : go cs False False

completeBareLiterals :: T.Text -> T.Text
completeBareLiterals t = T.pack (go (T.unpack t) False False)
  where
    go :: String -> Bool -> Bool -> String
    go [] _ _ = []
    go (c : cs) inStr esc
        | inStr =
            if esc
                then c : go cs True False
                else case c of
                    '\\' -> c : go cs True True
                    '"' -> c : go cs False False
                    _ -> c : go cs True False
        | c == '"' = c : go cs True False
        | c == 'n' = completeOrKeep c "ull" cs
        | c == 't' = completeOrKeep c "rue" cs
        | c == 'f' = completeOrKeep c "alse" cs
        | c == '-' && isDelimiterStart cs = '-' : '0' : go cs False False
        | otherwise = c : go cs False False

    isDelimiterStart :: String -> Bool
    isDelimiterStart [] = True
    isDelimiterStart (x : _) = isSpace x || x == ',' || x == '}' || x == ']'

    completeOrKeep :: Char -> String -> String -> String
    completeOrKeep first suffix restInput =
        let (matched, remainingInput, remainingSuffix) = matchPrefix restInput suffix
         in if null remainingSuffix
                then first : matched ++ go remainingInput False False
                else
                    if isDelimiterStart remainingInput
                        then first : matched ++ remainingSuffix ++ go remainingInput False False
                        else first : go restInput False False

    matchPrefix :: String -> String -> (String, String, String)
    matchPrefix input expected = goPrefix input expected []
      where
        goPrefix rest [] acc = (reverse acc, rest, [])
        goPrefix [] remain acc = (reverse acc, [], remain)
        goPrefix fullRest@(r : rs) remainExpected@(tch : tchs) acc
            | r == tch = goPrefix rs tchs (r : acc)
            | otherwise = (reverse acc, fullRest, remainExpected)

insertNullForDanglingKeysNoColon :: T.Text -> T.Text
insertNullForDanglingKeysNoColon t = T.pack (go (T.unpack t) False False [] Nothing)
  where
    go :: String -> Bool -> Bool -> [Char] -> Maybe Char -> String
    go [] _ _ _ _ = []
    go s@('"' : _) False _ stack prevSigil =
        let (strLit, rest, _closed) = readString s
            nextNonSpace = case dropWhile isSpace rest of
                [] -> Nothing
                (x : _) -> Just x
            inObject = case stack of
                ('{' : _) -> True
                _ -> False
            keyPosition = case prevSigil of
                Just '{' -> True
                Just ',' -> True
                _ -> False
            isProperKey = nextNonSpace == Just ':'
            isDanglingKey = inObject && keyPosition && not isProperKey
         in if isDanglingKey
                then case nextNonSpace of
                    Just '}' -> strLit ++ ": null" ++ go rest False False stack (Just '"')
                    Just ']' -> strLit ++ ": null }" ++ go rest False False stack (Just '"')
                    _ -> strLit ++ ": null" ++ go rest False False stack (Just '"')
                else strLit ++ go rest False False stack (Just '"')
    go (c : cs) inStr esc stack prevSigil
        | inStr =
            if esc
                then c : go cs True False stack prevSigil
                else case c of
                    '\\' -> c : go cs True True stack prevSigil
                    '"' -> c : go cs False False stack (Just '"')
                    _ -> c : go cs True False stack prevSigil
        | otherwise =
            if c == '"'
                then go (c : cs) False False stack prevSigil
                else case c of
                    '{' -> c : go cs False False ('{' : stack) (Just '{')
                    '}' -> c : go cs False False (pop '{' stack) (Just '}')
                    '[' -> c : go cs False False ('[' : stack) (Just '[')
                    ']' -> c : go cs False False (pop '[' stack) (Just ']')
                    ch ->
                        let nextPrev = if isSpace ch then prevSigil else Just ch
                         in ch : go cs False False stack nextPrev

    pop :: Char -> [Char] -> [Char]
    pop expected (x : xs) | x == expected = xs
    pop _ xs = xs

    readString :: String -> (String, String, Bool)
    readString ('"' : cs) =
        let (content, rest, closed) = goStr cs False
         in ('"' : content, rest, closed)
    readString xs = ("", xs, False)

    goStr :: String -> Bool -> (String, String, Bool)
    goStr [] _ = ([], [], False)
    goStr (c : cs) esc
        | esc =
            let (tail', rest, closed) = goStr cs False
             in (c : tail', rest, closed)
        | c == '\\' =
            let (tail', rest, closed) = goStr cs True
             in (c : tail', rest, closed)
        | c == '"' = ('"' : [], cs, True)
        | otherwise =
            let (tail', rest, closed) = goStr cs False
             in (c : tail', rest, closed)
