"""Run the Mac launcher's fresh-install and already-enrolled paths using mocks, never real sudo/MDM."""
import atexit
import os
from pathlib import Path
import pty
import subprocess
import tempfile
source = Path(__file__).with_name('install-macos.sh').read_text()
# The two filesystem probes are rerouted to mock-controlled flags; everything else runs as shipped.
for old, new in [('[[ -e /opt/orbit ]]', '[[ $mock_fleet == 1 ]]'), ('[[ -f $package && ! -L $package ]]', '[[ 1 == 1 ]]'),
                 ('[[ -f $REMOTE_SUPPORT_DIR/meshagent.msh ]] && grep -qxF "$mesh_id" "$REMOTE_SUPPORT_DIR/meshagent.msh"', 'mock_rs_settings "$mesh_id"')]:
    assert source.count(old) == 1, old
    source = source.replace(old, new)
with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', dir=os.environ.get('TMPDIR', str(Path.home())), delete=False) as f:
    f.write(source)
    path = f.name
atexit.register(lambda: Path(path).unlink(missing_ok=True))
probe = r'''
source "$1"
mode=$2 mock_fleet=$3 mock_rs=$4
agent_hash=5bad4449e361b0a1f35e660f5d2b6cfdb11abf4adbb859719fccc6987800aca9
uname() { if [[ ${1:-} == -m ]]; then echo arm64; else echo Darwin; fi; }
profiles() { echo 'MDM enrollment: No'; }
curl() { echo "CURL:${*: -3:1}" >&2; [[ $mode != download-failure ]]; }
read() { if [[ $mode == decline ]]; then answer=n; else answer=y; fi; }
sleep() { :; }
mock_rs_settings() { [[ $mock_rs == 1 ]] && [[ $1 == MeshID=0x* ]]; }
launchctl() { [[ $mock_rs == 1 ]]; }
shasum() {
 case "${*: -1}" in
  /mock/stage/meshagent) if [[ $mode == agent-bad-hash ]]; then echo 'bad mock'; else echo "$agent_hash  mock"; fi ;;
  *meshagent) if [[ $mode == agent-download-bad ]]; then echo 'bad mock'; else echo "$agent_hash  mock"; fi ;;
  *) if [[ $mode == user-bad-hash ]]; then echo 'bad mock'; else echo 'a007378525fec19e7fab0d8dfcccd1c17005dffb6256e09d22ef235cedbc5ae2  mock'; fi ;;
 esac
}
sudo() {
 echo "MOCK:$1" >&2
 [[ $1 != "$mode" ]] || return 1
 case "$1" in
  mktemp) echo /mock/stage ;;
  cat) if [[ $mode == foreign ]]; then echo https://fleet.other.example; else echo https://mdm.noovoleum.site; fi ;;
  shasum) if [[ $mode == bad-hash && ${*: -1} == *fleet.pkg ]]; then echo 'bad mock'; else shift; shasum "$@"; fi ;;
  tee) cat >/dev/null ;;
  /bin/bash) echo MOCK:meshagent-install >&2; [[ $mode == agent-dead ]] || mock_rs=1 ;;
 esac
 return 0
}
if main; then echo RESULT:success; else echo RESULT:failure; fi
'''


def run(mode, fleet, rs):
    master, slave = pty.openpty()
    try:
        r = subprocess.run(['/bin/bash', '-c', probe, '_', path, mode, str(fleet), str(rs)], stdin=slave,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15)
    finally:
        os.close(master); os.close(slave)
    assert r.returncode == 0, r.stdout
    return r.stdout


# Fresh Mac: Fleet then remote support; each failure stops before later side effects and cleans up.
for mode in ['download-failure', 'user-bad-hash', 'cp', 'chmod', 'bad-hash', 'installer', 'agent-bad-hash', 'agent-dead', 'none']:
    out = run(mode, 0, 0)
    if mode == 'none':
        assert 'RESULT:success' in out and 'Fleet installed.' in out and 'Remote support installed.' in out and 'Turn on MDM' in out, out
        assert 'CURL:https://remote-agent.noovoleum.site/meshagents?id=29' in out, out
        assert out.index('MOCK:installer') < out.index('MOCK:meshagent-install'), out
    else:
        assert 'RESULT:failure' in out and 'Remote support installed.' not in out, out
        if mode not in ('installer', 'agent-bad-hash', 'agent-dead'): assert 'MOCK:installer' not in out, out
        if mode in ('agent-bad-hash',): assert 'MOCK:meshagent-install' not in out, out
    if mode in ('user-bad-hash', 'download-failure'):
        assert 'MOCK:' not in out, out
    else:
        assert 'MOCK:rm' in out, out

# Already-enrolled Mac: never touches the Fleet package or MDM status; only installs remote support.
out = run('none', 1, 0)
assert 'RESULT:success' in out and 'Remote support installed.' in out, out
assert 'MOCK:installer' not in out and 'fleet-macos.pkg' not in out and 'Turn on MDM' not in out, out
out = run('none', 1, 1)
assert 'RESULT:success' in out and 'Nothing to do' in out and 'MOCK:' not in out and 'CURL:' not in out, out
for mode in ['foreign', 'agent-bad-hash', 'agent-dead', 'decline', 'agent-download-bad']:
    out = run(mode, 1, 0)
    assert 'RESULT:failure' in out and 'Remote support installed.' not in out and 'MOCK:installer' not in out, (mode, out)
    if mode == 'foreign': assert 'not recognised' in out and 'CURL:' not in out, out
    if mode == 'agent-dead': assert 'rerunning this command is safe' in out, out
    if mode == 'decline': assert 'Install Noovoleum remote support? [Y/n]' in out and 'Cancelled.' in out and 'MOCK:' not in out and 'CURL:' not in out, out
    if mode == 'agent-download-bad': assert 'Remote support agent mismatch' in out and 'MOCK:cp' not in out and 'MOCK:meshagent-install' not in out, out

print('PASS: online Mac launcher fresh install + remote support, already-enrolled remote-support-only path, '
      'no-op, foreign Fleet refusal, staged hash refusals, installer/agent failures and cleanup.')
