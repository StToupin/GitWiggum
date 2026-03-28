# aeson-decode-loose

Best-effort JSON decoding for partially streamed or unterminated JSON text.

## What it does

- tries normal `aeson` decoding first
- if that fails, repairs common incomplete JSON shapes
- decodes the repaired JSON

The repair pass handles common stream truncation issues:

- unterminated strings
- missing closing `}` / `]`
- dangling keys like `{"name": }` or `{"name"}`
- trailing commas before closers
- partial `null` literals (`n`, `nu`, `nul`)
