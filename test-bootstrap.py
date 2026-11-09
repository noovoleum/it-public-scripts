"""Exercise the exact README Mac one-liner without executing enrollment."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

readme = Path(__file__).with_name('README.md').read_text()
match = re.search(r'```bash\n(.*?)```', readme, re.S)
assert match, 'Missing Mac starting command'
command = match[1].strip()
assert 'it-public-scripts/main/install-macos.sh' in command
assert 'shasum' not in command, 'Mutable launcher must not use a stale script pin'
with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
    # Mock download writes a harmless script. Its stdin must remain interactive.
    probe = r'''
curl() {
    local dest
    while [[ $# -gt 0 ]]; do
        if [[ $1 == -o ]]; then dest=$2; shift; fi
        shift
    done
    printf '%s\n' "$dest" > "$STAGE_LOG"
    printf '%s\n' 'read -r answer; echo "FIXTURE:$answer"; exit "${CHILD_EXIT:-0}"' > "$dest"
    [[ ${DOWNLOAD_FAIL:-0} == 0 ]]
}
'''
    for mode in ('success', 'download-failure', 'child-failure'):
        log = Path(directory, 'stage')
        result = subprocess.run(['/bin/bash', '-c', probe + command], input='yes\n',
                                capture_output=True, text=True, env={**os.environ,
                                'TMPDIR': directory, 'STAGE_LOG': str(log),
                                'DOWNLOAD_FAIL': str(int(mode == 'download-failure')),
                                'CHILD_EXIT': '7' if mode == 'child-failure' else '0'})
        assert (result.returncode == 0) == (mode == 'success'), result
        assert ('FIXTURE:yes' in result.stdout) == (mode != 'download-failure'), result
        assert not Path(log.read_text().strip()).exists(), 'Staging file retained'
print('PASS: stable-main Mac bootstrap preserves stdin, download refusal, exit propagation and cleanup.')
