#!/bin/bash
# Public enrollment package; direct HTTPS download and pinned-byte verification.
set -euo pipefail
main() (
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    [[ $(uname -s) == Darwin && $EUID -ne 0 && -t 0 ]] || { echo 'Run in an ordinary Mac Terminal, without sudo.' >&2; return 1; }
    [[ ! -e /opt/orbit ]] || { echo 'Fleet is already installed. Ask IT to verify it; no reinstall performed.'; return; }
    local status package hash='a007378525fec19e7fab0d8dfcccd1c17005dffb6256e09d22ef235cedbc5ae2' answer stage
    status=$(profiles status -type enrollment) || return 1
    printf '%s\n' "$status" | grep -Eq '^MDM enrollment: No$' || { echo 'Existing or unknown MDM. Contact IT rather than replacing it.' >&2; return 1; }
    local download
    download=$(mktemp -d "${TMPDIR:-/private/tmp}/noovoleum-enroll.XXXXXXXX") || return 1
    trap 'rm -rf -- "$download"' EXIT
    package="$download/fleet-macos.pkg"
    echo 'Downloading Noovoleum Fleet installer; no login required.'
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' 'https://github.com/noovoleum/it-public-scripts/releases/download/enrollment-v1/fleet-macos.pkg' -o "$package" || return 1
    [[ -f $package && ! -L $package ]] || { echo 'Installer download failed.' >&2; return 1; }
    [[ $(shasum -a 256 "$package" | cut -d ' ' -f1) == "$hash" ]] || { echo 'Package mismatch; nothing installed. Contact IT.' >&2; return 1; }
    echo 'This IT-generated package has no Noovoleum Developer ID signature. Its exact bytes are verified against the approved hash in this launcher.'
    echo 'Only proceed on an IT-approved work device. Native management-profile consent is still required.'
    read -r -p 'Type INSTALL to approve: ' answer
    [[ $answer == INSTALL ]] || { echo 'Cancelled.' >&2; return 1; }
    sudo -v || return 1
    stage=$(sudo mktemp -d /private/var/root/noovoleum-enroll.XXXXXXXX) || return 1
    trap 'sudo rm -rf -- "$stage"; rm -rf -- "$download"' EXIT
    sudo cp "$package" "$stage/fleet.pkg" || return 1
    sudo chmod 600 "$stage/fleet.pkg" || return 1
    [[ $(sudo shasum -a 256 "$stage/fleet.pkg" | cut -d ' ' -f1) == "$hash" ]] || { echo 'Staged package mismatch.' >&2; return 1; }
    sudo installer -pkg "$stage/fleet.pkg" -target / || return 1
    echo 'Installed. Open Fleet Desktop > My device > Turn on MDM, then approve the expected Noovoleum profile in System Settings. IT verifies fresh check-in and MDM On separately.'
)
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
