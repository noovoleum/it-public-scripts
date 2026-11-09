#Requires -Version 5.1
# Public enrollment package; direct HTTPS download and pinned-byte verification.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Assert-NativePowerShell {
    param([bool]$Is64BitOS, [bool]$Is64BitProcess)
    if ($Is64BitOS -and -not $Is64BitProcess) { throw 'Open native 64-bit PowerShell as administrator, not Windows PowerShell (x86), and run again.' }
}
function Remove-EnrollmentStage {
    [CmdletBinding()]
    param([string]$Path)
    try { Remove-Item -LiteralPath $Path -Recurse -Force } catch { Write-Warning "Could not remove protected installer staging folder $Path. Ask IT to delete it; do not reinstall solely because cleanup failed." }
}
function Assert-NoExistingMdm {
    if (-not ('NoovoleumMdmRegistration' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NoovoleumMdmRegistration {
    [DllImport("MDMRegistration.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    public static extern int IsDeviceRegisteredWithManagement(
        [MarshalAs(UnmanagedType.Bool)] out bool registered,
        uint bufferLength,
        IntPtr userName);
}
'@
    }
    $registered = $false
    $result = [NoovoleumMdmRegistration]::IsDeviceRegisteredWithManagement([ref]$registered, 0, [IntPtr]::Zero)
    if ($result -ne 0) { throw "Could not determine MDM enrollment (HRESULT $result). Nothing installed; contact IT." }
    if ($registered) { throw 'Existing MDM detected. Contact IT; no migration or replacement is performed.' }
}
function Install-NoovoleumFleet {
    Assert-NativePowerShell ([Environment]::Is64BitOperatingSystem) ([Environment]::Is64BitProcess)
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Run on Windows.' }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Open PowerShell as administrator and run the command again.' }
    if (-not [Environment]::UserInteractive -or (Get-Process -Id $PID).SessionId -eq 0) { throw 'Sign in interactively; do not run from a service.' }
    if (Get-Service -Name Orbit -ErrorAction SilentlyContinue) { Write-Output 'Fleet is already installed. Contact IT to verify it; no reinstall performed.'; return }
    Assert-NoExistingMdm
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        'AMD64' { $name='fleet-windows-amd64.msi'; $hash='52569b1cdbbda4441bda63794f086a0ce63344dfb7d3c91c6967572b59cd6b22' }
        'ARM64' { $name='fleet-windows-arm64.msi'; $hash='dea536c3cf567b0919ef7a3315c621fdc6670327a7507e31fee86c5a1f2e2bfd' }
        default { throw 'Unsupported Windows architecture.' }
    }
    Write-Output 'This IT-generated MSI has no Noovoleum publisher signature. This launcher verifies its exact approved hash.'
    Write-Output 'Fleet Windows MDM can change Defender tamper protection. Proceed only on an IT-approved work device after IT has approved this security impact.'
    if ((Read-Host 'Type INSTALL to approve installation and the disclosed security-policy impact') -cne 'INSTALL') { throw 'Cancelled.' }
    $stage = Join-Path $env:ProgramFiles ('Noovoleum-enroll-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $stage
    try {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
            $identity = New-Object Security.Principal.SecurityIdentifier($sid)
            $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $stage -AclObject $acl
        $staged = Join-Path $stage 'fleet.msi'
        Write-Output 'Downloading Noovoleum Fleet installer; no login required.'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri ('https://github.com/noovoleum/it-public-scripts/releases/download/enrollment-v1/' + $name) -OutFile $staged
        if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash -ine $hash) { throw 'Package hash mismatch; nothing installed. Contact IT.' }
        $process = Start-Process "$env:SystemRoot\System32\msiexec.exe" -ArgumentList @('/i',('"'+$staged+'"'),'/norestart') -Wait -PassThru
        if ($process.ExitCode -notin @(0,3010)) { throw "Installer failed: $($process.ExitCode). Contact IT." }
        Write-Output 'Installed. Open Fleet Desktop > My device for MDM instructions. IT verifies fresh check-in and MDM On separately.'
        if ($process.ExitCode -eq 3010) { Write-Output 'Windows requests a restart; save your work and arrange it yourself. No automatic restart occurs.' }
    } finally { Remove-EnrollmentStage -Path $stage }
}
if ($MyInvocation.InvocationName -ne '.') {
    try { Install-NoovoleumFleet } catch { Write-Error $_ -ErrorAction Continue; exit 1 }
}
