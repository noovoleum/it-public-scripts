#!/bin/bash
# Public enrollment package; direct HTTPS download and pinned-byte verification.
set -euo pipefail
confirm_enrollment() {
    local answer
    [[ -t 0 ]] || { echo 'Interactive input required; no consent assumed.' >&2; return 2; }
    while true; do
        printf '%s [Y/n]: ' "$1"
        IFS= read -r answer || { echo 'No input; no consent assumed.' >&2; return 2; }
        case "$answer" in ''|y|Y) return 0 ;; n|N) return 1 ;; *) echo 'Please enter y or n, or press Enter for yes.' ;; esac
    done
}
request_miradore_migration() {
    local status=$1 endpoint host
    if printf '%s\n' "$status" | grep -Eq '^Enrolled via DEP: Yes'; then
        echo 'Automated Device Enrollment requires IT review; no profile removal or bypass performed.' >&2; return 1
    fi
    endpoint=$(printf '%s\n' "$status" | sed -n 's/^MDM server: //p')
    # Only a vendor HTTPS management endpoint qualifies, never a display-name match.
    host=${endpoint#https://}; host=${host%%/*}
    case "$endpoint" in https://*) ;; *) echo 'Existing or unknown MDM. Contact IT.' >&2; return 1 ;; esac
    case "$host" in online.miradore.com|*.online.miradore.com) ;; *) echo 'Existing or unknown MDM. Contact IT.' >&2; return 1 ;; esac
    case "$host" in *'@'*|*':'*|*'?'*|*'#'*) echo 'Unknown MDM endpoint. Contact IT.' >&2; return 1 ;; esac
    echo 'Miradore management detected. Removing it may remove managed certificates, apps, work data and settings. No reset or automatic removal is performed.'
    confirm_enrollment 'Continue to the manual Miradore migration instructions?' || return 1
    echo 'On macOS 15 or later: Apple menu > System Settings > General > Device Management. Select the Miradore Mobile Device Management profile, click Remove (-), and confirm only that profile.'
    echo 'On older macOS, search System Settings for Profiles (System Preferences > Profiles on macOS 12). If removal is blocked or the Mac uses Automated Device Enrollment, stop and contact IT. Never bypass the restriction.'
    echo 'Rerun this enrollment command after IT-approved removal. The installer will require MDM enrollment: No before continuing.'
    return 1
}
main() (
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    [[ $(uname -s) == Darwin && $EUID -ne 0 && -t 0 ]] || { echo 'Run in an ordinary Mac Terminal, without sudo.' >&2; return 1; }
    [[ ! -e /opt/orbit ]] || { echo 'Fleet is already installed. Ask IT to verify it; no reinstall performed.'; return; }
    local status package hash='a007378525fec19e7fab0d8dfcccd1c17005dffb6256e09d22ef235cedbc5ae2' answer stage
    status=$(profiles status -type enrollment) || return 1
    if ! printf '%s\n' "$status" | grep -Eq '^MDM enrollment: No$'; then
        request_miradore_migration "$status" || return 1
        return 1
    fi
    if printf '%s\n' "$status" | grep -Eq '^Enrolled via DEP: Yes'; then
        echo 'Automated Device Enrollment requires IT review; no bypass performed.' >&2; return 1
    fi
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
    confirm_enrollment 'Install Fleet?' || { echo 'Cancelled.' >&2; return 1; }
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
