#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C
umask 077

[[ $(uname -s) == Darwin ]] || { echo 'Run this in Mac Terminal.' >&2; exit 1; }
provision=false
if [[ ${1:-} == --provision ]]; then
    provision=true
    shift
    installer="$(dirname "$0")/install-macos.sh"
    [[ $EUID -ne 0 && -t 0 && -r $installer && $# -le 1 ]] || {
        echo 'Use ordinary Mac Terminal with install-macos.sh beside this script: bash inventory-macos.sh --provision [shared-folder]' >&2
        exit 1
    }
fi
if (( $# > 2 )); then echo 'Usage: bash inventory-macos.sh [shared-folder] [pass|fail|not_checked]' >&2; exit 1; fi
shared=${1:-${LAPTOP_INVENTORY_DIR:-}}
condition=${2:-}
keys=(screen keyboard trackpad charger camera audio wifi)
checks=()
if [[ -z $condition ]]; then
    [[ -t 0 ]] || { echo 'Use a terminal or supply a condition argument.' >&2; exit 1; }
    prompts=(
        'Screen: change brightness and check for cracks, lines or dead pixels'
        'Keyboard: type in TextEdit and test the keys'
        'Trackpad: move, click and scroll'
        'Charger: plug it in and verify the charging indicator'
        'Camera: open Photo Booth and verify the live image'
        'Audio: test the speakers and microphone'
        'Wi-Fi: connect and load a known page'
    )
    condition=pass
    for prompt in "${prompts[@]}"; do
        while true; do
            IFS= read -r -p "$prompt [y/n/Enter to skip]: " answer || {
                echo 'Input ended before the checklist finished; nothing saved or installed.' >&2
                exit 1
            }
            case $answer in
                y|Y) checks+=(pass); break ;;
                n|N) checks+=(fail); condition=fail; break ;;
                '') checks+=(not_checked); [[ $condition != pass ]] || condition=not_checked; break ;;
            esac
        done
    done
fi
case $condition in pass|fail|not_checked) ;; *) echo 'No valid condition supplied; nothing saved.' >&2; exit 1 ;; esac

hardware=$(system_profiler SPHardwareDataType -json 2>/dev/null || true)
power=$(system_profiler SPPowerDataType -detailLevel mini -json 2>/dev/null || true)
field() { printf '%s' "$1" | plutil -extract "$2" raw -o - -- - 2>/dev/null || true; }
serial=$(field "$hardware" SPHardwareDataType.0.serial_number | tr '[:lower:]' '[:upper:]')
if [[ ! $serial =~ ^[A-Z0-9][A-Z0-9-]{0,99}$ || $serial =~ ^(0+|NONE|UNKNOWN|DEFAULT|NA|SYSTEMSERIALNUMBER)$ ]]; then serial=''; fi
vault=$(fdesetup status 2>/dev/null || true)
case $vault in 'FileVault is On.'*) encryption=on ;; 'FileVault is Off.'*) encryption=off ;; *) encryption=unknown ;; esac
volume=/System/Volumes/Data
[[ -d $volume ]] || volume=/
# The startup data volume, not the sealed macOS system volume.
disk=$(df -kP "$volume" 2>/dev/null | awk 'NR==2 && $2 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ {printf "%.0f %.0f", $2*1024, $4*1024}' || true)
read -r capacity free <<< "$disk"

local_dir="$HOME/Library/Application Support/Noovoleum/Laptop Inventory"
mkdir -p "$local_dir"
tmp=$(mktemp "$local_dir/.inventory.XXXXXXXX")
shared_tmp=''
cleanup() {
    rm -f -- "$tmp"
    if [[ -n $shared_tmp ]]; then rm -f -- "$shared_tmp"; fi
}
trap cleanup EXIT
text() { if [[ -n $2 ]]; then plutil -insert "$1" -string "$2" "$tmp"; fi; }
number() { if [[ $2 =~ ^[0-9]+$ ]]; then plutil -insert "$1" -integer "$2" "$tmp"; fi; }
plutil -create xml1 "$tmp"
text collected_at_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
text serial "$serial"
text hostname "$(hostname -s)"
text manufacturer Apple
text model "$(sysctl -n hw.model 2>/dev/null || true)"
text os macOS
version=$(sw_vers -productVersion)
text os_version "$version (build $(sw_vers -buildVersion))"
text cpu "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
number memory_bytes "$(sysctl -n hw.memsize 2>/dev/null || true)"
number disk_capacity_bytes "$capacity"
number disk_free_bytes "$free"
number battery_charge_percent "$(field "$power" SPPowerDataType.0.sppower_battery_charge_info.sppower_battery_state_of_charge)"
number battery_cycle_count "$(field "$power" SPPowerDataType.0.sppower_battery_health_info.sppower_battery_cycle_count)"
health=$(field "$power" SPPowerDataType.0.sppower_battery_health_info.sppower_battery_health_maximum_capacity)
number battery_max_capacity_percent "${health%\%}"
text encryption "$encryption"
text manual_condition "$condition"
if [[ -n ${checks[0]:-} ]]; then
    plutil -insert manual_checks -dictionary "$tmp"
    for index in "${!checks[@]}"; do
        text "manual_checks.${keys[index]}" "${checks[index]}"
    done
fi
plutil -convert json "$tmp"

# ponytail: latest report per serial only; use an asset system if audit history is needed.
name="laptop-${serial:-unknown-$(uuidgen)}.json"
if [[ -d $local_dir/$name ]] || ! mv -fh -- "$tmp" "$local_dir/$name"; then
    echo 'Could not save the local report; nothing copied to the shared folder.' >&2
    exit 1
fi
printf 'Local report: %s\n' "$local_dir/$name"
[[ -n $serial ]] || { echo 'No usable serial. Local report only; verify the serial on the laptop label.' >&2; exit 1; }
if [[ -n $shared ]]; then
    if [[ $shared != /* || ! -d $shared || -d $shared/$name ]] || ! shared_tmp=$(mktemp "$shared/.inventory.XXXXXXXX") ||
        ! cp -- "$local_dir/$name" "$shared_tmp" || ! mv -fh -- "$shared_tmp" "$shared/$name"; then
        echo 'Shared save not confirmed. The local report is intact. Reconnect the folder and rerun.' >&2
        exit 1
    fi
    printf 'Shared report: %s\n' "$shared/$name"
else
    echo 'Local only: no shared folder configured.'
fi

if $provision; then
    IFS= read -r -p 'Continue to Fleet and IT remote support setup? [y/N]: ' answer || exit 1
    case $answer in y|Y) ;; *) echo 'Provisioning skipped. The inventory report is saved.'; exit 0 ;; esac
    echo 'Starting Fleet and Noovoleum remote support setup.'
    /bin/bash "$installer" || {
        status=$?
        echo 'Provisioning stopped. The inventory report is saved; follow the installer instructions.' >&2
        exit "$status"
    }
    echo 'Open Fleet Desktop > My device and finish any native enrollment prompts. IT must verify MDM On, fresh check-in, and the Snipe-IT record separately.'
fi
