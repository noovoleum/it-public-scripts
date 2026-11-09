"""Exercise short Mac command/bootstrap with harmless scripts and a real PTY."""
from pathlib import Path
import os
import pty
import re
import subprocess
import tempfile

root = Path(__file__).parent
command = re.search(r'```bash\n(.*?)```', (root / 'README.md').read_text(), re.S)[1].strip()
assert command == 'curl -fsSL https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/bootstrap-macos.sh | /bin/bash'
bootstrap = (root / 'bootstrap-macos.sh').read_text()
with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
    directory = Path(directory)
    truncated = directory / 'truncated.sh'
    truncated.write_text(bootstrap[:bootstrap.rindex(') </dev/tty')])
    fixture = directory / 'fixture.sh'
    fixture.write_text('read -r answer; echo "FIXTURE:$answer"; exit "${CHILD_EXIT:-0}"\n')
    # Mock only curl: first response is the real bootstrap, second is harmless fixture.
    curl = directory / 'curl'
    curl.write_text('''#!/bin/bash
if [[ "$*" == *bootstrap-macos.sh* ]]; then
    cat "$BOOTSTRAP"
else
    while [[ $# -gt 0 ]]; do
        if [[ $1 == -o ]]; then dest=$2; shift; fi
        shift
    done
    echo "$dest" > "$STAGE_LOG"
    cp "$FIXTURE" "$dest"
    [[ ${DOWNLOAD_FAIL:-0} == 0 ]]
fi
''')
    curl.chmod(0o700)
    for mode in ('success', 'download-failure', 'child-failure', 'noninteractive', 'truncated-bootstrap'):
        master, slave = pty.openpty()
        env = {**os.environ, 'PATH': str(directory) + ':' + os.environ['PATH'],
               'BOOTSTRAP': str(truncated if mode == 'truncated-bootstrap' else root / 'bootstrap-macos.sh'), 'FIXTURE': str(fixture),
               'TMPDIR': str(directory), 'STAGE_LOG': str(directory / 'stage'),
               'DOWNLOAD_FAIL': str(int(mode == 'download-failure')),
               'CHILD_EXIT': '7' if mode == 'child-failure' else '0'}
        # setsid + TIOCSCTTY gives the pipeline a controlling terminal for /dev/tty.
        import fcntl
        import termios
        def terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        try:
            proc = subprocess.Popen(['/bin/bash', '-c', command], stdin=slave if mode != 'noninteractive' else subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env,
                                    preexec_fn=terminal if mode != 'noninteractive' else os.setsid)
            os.write(master, b'yes\n')
            output = proc.communicate(timeout=10)[0].decode()
        finally:
            os.close(master)
            os.close(slave)
        assert (proc.returncode == 0) == (mode == 'success'), (mode, output)
        assert ('FIXTURE:yes' in output) == (mode in ('success', 'child-failure')), (mode, output)
        log = directory / 'stage'
        if log.exists():
            assert not Path(log.read_text().strip()).exists(), 'Staged download retained'
            log.unlink()
print('PASS: short Mac pipeline preserves terminal input, fails closed without terminal, and handles download/child failure and cleanup.')
