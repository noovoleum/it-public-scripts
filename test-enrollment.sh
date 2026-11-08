#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/enroll-macos.sh"
stage=$(mktemp -d "${TMPDIR:-$HOME}/noov-enroll-test.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
printf 'test data, not an installer' > "$stage/fleet.pkg"
hash=$(shasum -a 256 "$stage/fleet.pkg" | cut -d ' ' -f1)
pkgutil() { printf '%s\n' '1. Developer ID Installer: Test Company (ABCDEFGHIJ)'; }
spctl() { return 0; }
xcrun() { return 0; }
reject() { if "$@" >/dev/null 2>&1; then echo 'Expected rejection' >&2; exit 1; fi; }
verify_package "$stage/fleet.pkg" "$hash" ABCDEFGHIJ
reject verify_package "$stage/missing.pkg" "$hash" ABCDEFGHIJ
reject verify_package "$stage/fleet.pkg" invalid ABCDEFGHIJ
reject verify_package "$stage/fleet.pkg" "$hash" ZZZZZZZZZZ
printf 'modified' >> "$stage/fleet.pkg"
reject verify_package "$stage/fleet.pkg" "$hash" ABCDEFGHIJ
hash=$(shasum -a 256 "$stage/fleet.pkg" | cut -d ' ' -f1)
spctl() { return 1; }
reject verify_package "$stage/fleet.pkg" "$hash" ABCDEFGHIJ
spctl() { return 0; }
xcrun() { return 1; }
reject verify_package "$stage/fleet.pkg" "$hash" ABCDEFGHIJ
printf '%s\n' 'PASS: Mac hash, signer, assessment and notarization rejection checks (mocked native APIs; no installation).'
