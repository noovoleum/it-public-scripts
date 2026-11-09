# Run from administrator PowerShell. Only the installer child gets Bypass.
& {
    $ErrorActionPreference = 'Stop'
    $p = Join-Path $env:TEMP ('noov-enroll-' + [guid]::NewGuid() + '.ps1')
    try {
        Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/install-windows.ps1' -OutFile $p -ErrorAction Stop
        $ps = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
            Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
        } else {
            Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        }
        & $ps -NoProfile -ExecutionPolicy Bypass -File $p
        if ($LASTEXITCODE -ne 0) { throw "Enrollment stopped (exit $LASTEXITCODE). Follow the displayed instructions or contact it@noovoleum.com." }
    } finally {
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    }
}
