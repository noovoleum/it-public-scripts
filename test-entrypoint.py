"""Mock the entire Mac entrypoint: no sudo, packages or MDM operations run."""
import os
from pathlib import Path
import pty
import subprocess
import tempfile
import atexit

script = Path(__file__).with_name('enroll-macos.sh').resolve()
# Mock only the existing-install preflight; the entrypoint below is unchanged.
source = script.read_text()
guard = '[[ ! -e /opt/orbit ]]'
assert source.count(guard) == 1
source = source.replace(guard, '[[ 1 == 1 ]]')
with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', dir=os.environ.get('TMPDIR', str(Path.home())), delete=False) as temporary:
    temporary.write(source)
    test_source = temporary.name
atexit.register(lambda: Path(test_source).unlink(missing_ok=True))
probe = r'''
source "$1"
uname() { if [[ $1 == -s ]]; then echo Darwin; else echo arm64; fi; }
profiles() { echo 'MDM enrollment: No'; }
read() { approved=INSTALL; }
verify_package() { return 0; }
sudo() {
    echo "MOCK:$1"
    if [[ $1 == "$failure" ]]; then return 1; fi
    if [[ $1 == mktemp ]]; then echo /mock/private-stage; fi
    return 0
}
failure=$2
if main /mock/fleet.pkg ignored ignored; then
    echo RESULT:success
else
    echo RESULT:failure
fi
'''
for failure in ('cp', 'chown', 'chmod', '/bin/bash', 'installer', 'none'):
    master, slave = pty.openpty()
    try:
        result = subprocess.run(
            ['/bin/bash', '-c', probe, '_', test_source, failure], stdin=slave,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15,
        )
    finally:
        os.close(slave)
        os.close(master)
    output = result.stdout
    assert result.returncode == 0, output
    if failure == 'none':
        assert 'RESULT:success' in output and 'Installer completed.' in output, output
    else:
        assert 'RESULT:failure' in output and 'Installer completed.' not in output, output
        if failure != 'installer':
            assert 'MOCK:installer' not in output, output
    assert 'MOCK:rm' in output, output
print('PASS: conditional Mac entrypoint stops on each staging, verification and installation failure; mocked cleanup and success path checked.')
