#!/bin/sh
set -eu

make print-ghc-options GHC_RTS_FLAGS='' | tr ' ' '\n' > "$HIE_BIOS_OUTPUT"
echo "$HIE_BIOS_ARG" >> "$HIE_BIOS_OUTPUT"
printf '%s\n' \
    -iPlugins/ihp-auth-support \
    -iPlugins/ihp-oauth-github \
    -iPlugins/ihp-oauth-google \
    -iPlugins/ihp-oauth-microsoft \
    -iPlugins/ihp-sentry \
    -iPlugins/ihp-stripe \
    >> "$HIE_BIOS_OUTPUT"

# Keep HLS scoped to the main gitWiggum app/test sources. The default IHP bios
# script recurses through every *.hs file under the repo, which pulls in sibling
# projects and nested .direnv flake inputs and corrupts module loading.
find Application Config Git Plugins Test Web build -name '*.hs' >> "$HIE_BIOS_OUTPUT"
printf '%s\n' Main.hs Setup.hs >> "$HIE_BIOS_OUTPUT"
