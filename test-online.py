"""Run Mac launcher trust/staging failures using mocks, never real sudo/MDM."""
import atexit
import os
from pathlib import Path
import pty
import subprocess
import tempfile
source = Path(__file__).with_name('install-macos.sh').read_text()
for old, new in [('[[ ! -e /opt/orbit ]]', '[[ 1 == 1 ]]'), ('[[ -f $package && ! -L $package ]]', '[[ 1 == 1 ]]')]:
    assert source.count(old) == 1
    source = source.replace(old, new)
with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', dir=os.environ.get('TMPDIR', str(Path.home())), delete=False) as f:
    f.write(source)
    path = f.name
atexit.register(lambda: Path(path).unlink(missing_ok=True))
probe = r'''
source "$1"
mode=$2
uname() { echo Darwin; }
profiles() { echo 'MDM enrollment: No'; }
curl() { [[ $mode != download-failure ]]; }
read() { answer=y; }
shasum() { if [[ $mode == user-bad-hash ]]; then echo 'bad mock'; else echo 'a007378525fec19e7fab0d8dfcccd1c17005dffb6256e09d22ef235cedbc5ae2  mock'; fi; }
sudo() {
 echo "MOCK:$1" >&2
 [[ $1 != "$mode" ]] || return 1
 case "$1" in
  mktemp) echo /mock/stage ;;
  shasum) if [[ $mode == bad-hash ]]; then echo 'bad mock'; else shasum; fi ;;
 esac
 return 0
}
if main; then echo RESULT:success; else echo RESULT:failure; fi
'''
for mode in ['download-failure', 'user-bad-hash', 'cp', 'chmod', 'bad-hash', 'installer', 'none']:
    master, slave = pty.openpty()
    try:
        r = subprocess.run(['/bin/bash', '-c', probe, '_', path, mode], stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15)
    finally:
        os.close(master); os.close(slave)
    assert r.returncode == 0, r.stdout
    if mode == 'none':
        assert 'RESULT:success' in r.stdout and 'Installed.' in r.stdout, r.stdout
    else:
        assert 'RESULT:failure' in r.stdout and 'Installed.' not in r.stdout, r.stdout
        if mode != 'installer': assert 'MOCK:installer' not in r.stdout, r.stdout
    if mode in ('user-bad-hash', 'download-failure'):
        assert 'MOCK:' not in r.stdout, r.stdout
    else:
        assert 'MOCK:rm' in r.stdout, r.stdout

print('PASS: online Mac launcher mocked success, staged hash refusal, copy/mode/installer failures and cleanup.')
