#!/bin/bash
# Private, signed IT package required. No enrollment credentials in this file.
set -euo pipefail

verify_package() {
    local package=$1 expected_hash=$2 team=$3 signature
    [[ $expected_hash =~ ^[a-fA-F0-9]{64}$ && $team =~ ^[A-Z0-9]{10}$ ]] || { echo 'IT must supply the approved SHA-256 and Apple Team ID.' >&2; return 1; }
    [[ -f $package && ! -L $package && $package == *.pkg ]] || { echo 'Select a local .pkg supplied by IT.' >&2; return 1; }
    [[ $(shasum -a 256 "$package" | cut -d ' ' -f 1) == "$(printf '%s' "$expected_hash" | tr 'A-F' 'a-f')" ]] || { echo 'Package hash mismatch.' >&2; return 1; }
    signature=$(pkgutil --check-signature "$package") || return 1
    printf '%s\n' "$signature" | grep -Eq "Developer ID Installer: .+ \($team\)" || { echo 'Unexpected package signer.' >&2; return 1; }
    spctl --assess --type install "$package" || return 1
    # Assessment must work without fetching a missing notarization ticket.
    xcrun stapler validate "$package" >/dev/null || return 1
}

main() (
    [[ $(uname -s) == Darwin ]] || { echo 'Run this script on macOS.' >&2; return 1; }
    [[ $EUID -ne 0 ]] || { echo 'Run without sudo; elevation is requested only for installation.' >&2; return 1; }
    [[ -t 0 ]] || { echo 'Run in an interactive Terminal.' >&2; return 1; }
    local package=${1:-} expected_hash=${2:-} team=${3:-} mode=${4:-} stage approved architecture enrollment
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    [[ ! -e /opt/orbit ]] || { echo 'Fleet is already installed. Contact IT for verification; do not reinstall.' >&2; return 1; }
    enrollment=$(profiles status -type enrollment) || return 1
    printf '%s\n' "$enrollment" | grep -Eq '^MDM enrollment: No$' || { echo 'Existing or unknown MDM enrollment. Contact IT; no migration or replacement is performed.' >&2; return 1; }
    [[ $# -le 4 && ( -z $mode || $mode == --check-only ) ]] || { echo 'Usage: bash enroll-macos.sh [package.pkg SHA256 TEAMID [--check-only]]' >&2; return 1; }
    architecture=$(uname -m)
    [[ $architecture == arm64 || $architecture == x86_64 ]] || { echo 'Unsupported Mac architecture.' >&2; return 1; }
    [[ -n $package ]] || read -r -p 'Absolute path to the private IT-supplied PKG: ' package
    [[ -n $expected_hash ]] || read -r -p 'Approved SHA-256 from IT: ' expected_hash
    [[ -n $team ]] || read -r -p 'Approved Apple Team ID from IT: ' team
    [[ $package == /* ]] || { echo 'Use an absolute local package path.' >&2; return 1; }
    [[ $package != /Volumes/* ]] || { echo 'Copy the package to the local disk first.' >&2; return 1; }
    verify_package "$package" "$expected_hash" "$team" || return 1
    if [[ $mode == --check-only ]]; then echo 'Signature, notarization and hash verified; nothing installed.'; return; fi
    echo "Mac architecture: $architecture. IT must provide its matching or universal package."
    echo 'Existing Fleet/MDM profiles must be preserved. Do not remove or replace another MDM.'
    read -r -p 'Type INSTALL only if IT approved this device and this package architecture: ' approved
    [[ $approved == INSTALL ]] || { echo 'Cancelled; nothing installed.' >&2; return 1; }
    # Revalidate a root-owned private copy to prevent a user-writable file swap.
    sudo -v || return 1
    stage=$(sudo mktemp -d /private/var/root/noovoleum-enroll.XXXXXXXX) || return 1
    trap 'sudo rm -rf -- "$stage"' EXIT
    sudo cp -- "$package" "$stage/fleet.pkg" || return 1
    sudo chown root:wheel "$stage/fleet.pkg" || return 1
    sudo chmod 600 "$stage/fleet.pkg" || return 1
    sudo /bin/bash -c "$(declare -f verify_package); verify_package \"\$1\" \"\$2\" \"\$3\"" _ "$stage/fleet.pkg" "$expected_hash" "$team" || return 1
    sudo installer -pkg "$stage/fleet.pkg" -target / || return 1
    echo 'Installer completed. Open Fleet Desktop > My device > Turn on MDM and approve the profile in System Settings if needed.'
    echo 'IT must verify matching hardware identity, a fresh agent check-in and MDM On. Installer success alone is NOT enrollment confirmation.'
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
