#!/bin/bash
# Public enrollment package; direct HTTPS download and pinned-byte verification.
set -euo pipefail
# MeshCentral agent settings for group "Fleet managed". Like the Fleet enrollment key, they only let a device
# register itself for IT remote support; they grant no access to any device or to the server.
REMOTE_SUPPORT_SETTINGS='MeshName=Fleet managed
MeshType=2
MeshID=0x0009B3A90BCF1A9295A44ED2FCDA78B577C87C9B7234D974C7DD231D757EE0606351819E22B01C02EDC6FF731EC7607A
ServerID=3B468C4A97A484C366780B556721A18BB76F59B5F3705C90D594B094147E31166B4218B174CBCBE19C41B9BD37990081
MeshServer=wss://remote-agent.noovoleum.site:443/agent.ashx'
REMOTE_SUPPORT_DIR=/usr/local/mesh_services/meshagent
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
remote_support_installed() {
    local mesh_id
    mesh_id=$(printf '%s\n' "$REMOTE_SUPPORT_SETTINGS" | grep '^MeshID=')
    [[ -f $REMOTE_SUPPORT_DIR/meshagent.msh ]] && grep -qxF "$mesh_id" "$REMOTE_SUPPORT_DIR/meshagent.msh" \
        && launchctl print system/meshagent >/dev/null 2>&1
}
install_remote_support() {
    local download=$1 stage=$2 id hash
    # ponytail: pinned to the agent built by the deployed MeshCentral; repin when its image is upgraded.
    case $(uname -m) in
        arm64) id=29; hash='5bad4449e361b0a1f35e660f5d2b6cfdb11abf4adbb859719fccc6987800aca9' ;;
        x86_64) id=16; hash='d2b5d2dbb2f917354752449ec1b730c0b96f36b30d23a58c8350727e909fa1b4' ;;
        *) echo 'Unsupported Mac architecture.' >&2; return 1 ;;
    esac
    echo 'Installing Noovoleum remote support.'
    curl --fail --silent --show-error --proto '=https' "https://remote-agent.noovoleum.site/meshagents?id=$id" -o "$download/meshagent" || return 1
    [[ $(shasum -a 256 "$download/meshagent" | cut -d ' ' -f1) == "$hash" ]] || { echo 'Remote support agent mismatch; not installed. Fleet is unaffected. Contact IT.' >&2; return 1; }
    sudo cp "$download/meshagent" "$stage/meshagent" || return 1
    sudo chmod 700 "$stage/meshagent" || return 1
    [[ $(sudo shasum -a 256 "$stage/meshagent" | cut -d ' ' -f1) == "$hash" ]] || { echo 'Staged remote support agent mismatch.' >&2; return 1; }
    printf '%s\n' "$REMOTE_SUPPORT_SETTINGS" | sudo tee "$stage/meshagent.msh" >/dev/null || return 1
    # The installed agent must be readable outside root; inventory and staging stay private.
    sudo /bin/bash -c 'umask 022 && cd "$1" && ./meshagent -fullinstall --copy-msh=1' _ "$stage" >/dev/null || return 1
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do remote_support_installed && break; sleep 1; done
    remote_support_installed || { echo 'Remote support did not start. Fleet is unaffected; rerunning this command is safe. Contact IT if it fails again.' >&2; return 1; }
    echo 'Remote support installed.'
}
remote_support_permissions_hint() {
    echo 'For IT screen sharing, open System Settings > Privacy & Security and turn on "meshagent" under both Screen & System Audio Recording and Accessibility. Screen sharing still asks for your approval each time.'
}
main() (
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    [[ $(uname -s) == Darwin && $EUID -ne 0 && -t 0 ]] || { echo 'Run in an ordinary Mac Terminal, without sudo.' >&2; return 1; }
    local status package hash='a007378525fec19e7fab0d8dfcccd1c17005dffb6256e09d22ef235cedbc5ae2' stage fleet=install
    if [[ -e /opt/orbit ]]; then
        remote_support_installed && { echo 'Fleet and remote support are already installed. Nothing to do.'; remote_support_permissions_hint; return 0; }
        fleet=none
    fi
    local download
    download=$(mktemp -d "${TMPDIR:-/private/tmp}/noovoleum-enroll.XXXXXXXX") || return 1
    trap 'rm -rf -- "$download"' EXIT
    if [[ $fleet == none ]]; then
        echo 'Fleet is already installed. Noovoleum remote support lets IT help you: screen sharing asks for your approval each time, and IT file or terminal access shows a notification.'
        confirm_enrollment 'Install Noovoleum remote support?' || { echo 'Cancelled.' >&2; return 1; }
        sudo -v || return 1
        # The Fleet package for another server must never get our remote-support agent.
        [[ $(sudo cat /opt/orbit/fleet_url.txt 2>/dev/null) == 'https://mdm.noovoleum.site' ]] || { echo 'The installed Fleet agent is not recognised as the Noovoleum agent. Nothing changed; contact IT.' >&2; return 1; }
    else
        status=$(profiles status -type enrollment) || return 1
        if ! printf '%s\n' "$status" | grep -Eq '^MDM enrollment: No$'; then
            request_miradore_migration "$status" || return 1
            return 1
        fi
        if printf '%s\n' "$status" | grep -Eq '^Enrolled via DEP: Yes'; then
            echo 'Automated Device Enrollment requires IT review; no bypass performed.' >&2; return 1
        fi
        package="$download/fleet-macos.pkg"
        echo 'Downloading Noovoleum Fleet installer; no login required.'
        curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' 'https://github.com/noovoleum/it-public-scripts/releases/download/enrollment-v1/fleet-macos.pkg' -o "$package" || return 1
        [[ -f $package && ! -L $package ]] || { echo 'Installer download failed.' >&2; return 1; }
        [[ $(shasum -a 256 "$package" | cut -d ' ' -f1) == "$hash" ]] || { echo 'Package mismatch; nothing installed. Contact IT.' >&2; return 1; }
        echo 'This IT-generated package has no Noovoleum Developer ID signature. Its exact bytes are verified against the approved hash in this launcher.'
        echo 'Only proceed on an IT-approved work device. Native management-profile consent is still required. Noovoleum remote support is installed too: screen sharing asks for your approval each time.'
        confirm_enrollment 'Install Fleet and remote support?' || { echo 'Cancelled.' >&2; return 1; }
        sudo -v || return 1
    fi
    stage=$(sudo mktemp -d /private/var/root/noovoleum-enroll.XXXXXXXX) || return 1
    trap 'sudo rm -rf -- "$stage"; rm -rf -- "$download"' EXIT
    if [[ $fleet == install ]]; then
        sudo cp "$package" "$stage/fleet.pkg" || return 1
        sudo chmod 600 "$stage/fleet.pkg" || return 1
        [[ $(sudo shasum -a 256 "$stage/fleet.pkg" | cut -d ' ' -f1) == "$hash" ]] || { echo 'Staged package mismatch.' >&2; return 1; }
        sudo installer -pkg "$stage/fleet.pkg" -target / || return 1
        echo 'Fleet installed.'
    fi
    install_remote_support "$download" "$stage" || return 1
    remote_support_permissions_hint
    if [[ $fleet == install ]]; then
        echo 'Installed. Open Fleet Desktop > My device > Turn on MDM, then approve the expected Noovoleum profile in System Settings. IT verifies fresh check-in and MDM On separately.'
    fi
)
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
