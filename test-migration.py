"""Exercise actual Mac consent using a PTY; no management/installation actions."""
from pathlib import Path
import os
import pty
import subprocess
import termios

source = str(Path(__file__).with_name('install-macos.sh'))
for answer, expected in [(b'\n',0),(b'y\n',0),(b'Y\n',0),(b'n\n',1),(b'N\n',1),(b'bad\ny\n',0),(b'\x04',2)]:
    master, slave = pty.openpty()
    attrs = termios.tcgetattr(slave)
    attrs[3] &= ~termios.ECHO
    termios.tcsetattr(slave, termios.TCSANOW, attrs)
    proc = subprocess.Popen(['/bin/bash','-c','source "$1"; confirm_enrollment Continue','_',source],stdin=slave,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    os.write(master, answer)
    try:
        output = proc.communicate(timeout=5)[0]
    finally:
        os.close(master); os.close(slave)
    assert proc.returncode == expected, (answer,proc.returncode,output)
proc = subprocess.run(['/bin/bash','-c','source "$1"; confirm_enrollment Continue','_',source],input=b'',capture_output=True)
assert proc.returncode == 2
for url, accepted in [('https://online.miradore.com/mdm',True),('https://tenant.online.miradore.com/mdm',True),('https://online.miradore.com.attacker.test/mdm',False),('https://example.com/miradore.com',False),('https://user@online.miradore.com/mdm',False),('http://online.miradore.com/mdm',False)]:
    command = 'source "$1"; confirm_enrollment() { return 0; }; request_miradore_migration "MDM enrollment: Yes\nMDM server: $2"'
    proc = subprocess.run(['/bin/bash','-c',command,'_',source,url],capture_output=True,text=True)
    assert proc.returncode != 0
    assert ('Select the Miradore Mobile Device Management profile' in proc.stdout) == accepted, (url,proc.stdout)
proc = subprocess.run(['/bin/bash','-c','source "$1"; confirm_enrollment() { echo SHOULD_NOT_PROMPT; }; request_miradore_migration "Enrolled via DEP: Yes\nMDM enrollment: Yes\nMDM server: https://online.miradore.com/mdm"','_',source],capture_output=True,text=True)
assert proc.returncode != 0 and 'SHOULD_NOT_PROMPT' not in proc.stdout and 'Select the Miradore' not in proc.stdout, proc.stdout
print('PASS: Mac blank/y/n/invalid/EOF/noninteractive consent, ADE refusal and vendor-only manual-migration stop.')
