#!/bin/bash
# Keep all executable code in one compound command; consent reads the terminal,
# never the curl pipe. A truncated response cannot execute an incomplete block.
(
    set -eu
    p=$(mktemp) || exit 1
    trap 'rm -f "$p"' EXIT
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        'https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/install-macos.sh' -o "$p" || exit 1
    /bin/bash "$p"
) </dev/tty
