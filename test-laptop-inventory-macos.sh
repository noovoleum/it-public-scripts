#!/bin/bash
# Run on a Mac with a hardware serial; keep reports on this machine.
set -euo pipefail
umask 077
script="$(dirname "$0")/inventory-macos.sh"
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
export HOME="$stage/home"
mkdir "$HOME" "$stage/shared"
for condition in pass fail; do
    /bin/bash "$script" "$stage/shared" "$condition" >"$stage/output"
done
set -- "$stage/shared"/*.json
[[ $# == 1 && -f $1 ]]
field() { /usr/bin/plutil -extract "$1" raw -o - "$2"; }
[[ ${1##*/} == "laptop-$(field serial "$1").json" ]]
[[ $(field manual_condition "$1") == fail && $(field os "$1") == macOS ]]
[[ $(field memory_bytes "$1") -gt 0 && $(field disk_capacity_bytes "$1") -gt 0 ]]
if /bin/bash "$script" "$stage/missing" not_checked >"$stage/output" 2>"$stage/error"; then
    echo 'Missing share was reported as success.' >&2
    exit 1
fi
grep -q 'Shared save not confirmed' "$stage/error"
[[ $(field manual_condition "$HOME/Library/Application Support/Noovoleum/Laptop Inventory/${1##*/}") == not_checked ]]
bundle="$stage/bundle"
mkdir "$bundle"
cp "$script" "$bundle/inventory-macos.sh"
cat > "$bundle/install-macos.sh" <<'FIXTURE'
#!/bin/bash
set -eu
set -- "$HOME/../shared"/*.json
[[ $# == 1 && -f $1 ]]
[[ $(/usr/bin/plutil -extract manual_checks.keyboard raw -o - "$1") == fail ]]
[[ $(/usr/bin/plutil -extract manual_condition raw -o - "$1") == fail ]]
echo 'FIXTURE: provision called after report'
exit "${INSTALL_RESULT:-0}"
FIXTURE
# A PTY drives the real checklist and harmless installer boundary, not the production installer.
python3 - "$bundle/inventory-macos.sh" "$stage/shared" <<'PY'
import errno, os, pty, select, subprocess, sys, time
for installer_exit, approval in ((0, b''), (0, b'y'), (7, b'y')):
    master, slave = pty.openpty()
    proc = subprocess.Popen(['/bin/bash', sys.argv[1], '--provision', sys.argv[2]],
                            stdin=slave, stdout=slave, stderr=slave,
                            env={**os.environ, 'INSTALL_RESULT': str(installer_exit)})
    # Keep the slave open until buffered output is read, even after the child exits.
    output = b''
    try:
        for check, answer in zip((b'Screen', b'Screen', b'Keyboard', b'Trackpad', b'Charger', b'Camera', b'Audio', b'Wi-Fi'), b'xynyyyyy'):
            deadline = time.monotonic() + 10
            while check not in output or b'[y/n/Enter to skip]' not in output:
                assert select.select([master], [], [], max(0, deadline - time.monotonic()))[0], output
                output += os.read(master, 4096)
            output = b''
            os.write(master, bytes([answer]) + b'\n')
        deadline = time.monotonic() + 25
        while b'setup? [y/N]' not in output:
            assert select.select([master], [], [], max(0, deadline - time.monotonic()))[0], output
            output += os.read(master, 4096)
        os.write(master, approval + b'\n')
        assert proc.wait(timeout=25) == installer_exit
        while select.select([master], [], [], 0)[0]:
            try:
                data = os.read(master, 4096)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not data:
                break
            output += data
        assert (b'FIXTURE: provision called after report' in output) == bool(approval)
        assert (b'Provisioning skipped. The inventory report is saved.' in output) == (not approval)
        assert (b'MDM On' in output) == (bool(approval) and installer_exit == 0)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=5)
        os.close(master)
PY
echo 'PASS: native Mac inventory, individual checks, local fallback, and staged installer outcomes.'
