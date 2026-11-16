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
function Assert-EnrollmentAdministrator {
    param([bool]$IsAdministrator)
    if (-not $IsAdministrator) { throw 'Administrator PowerShell is required. Nothing installed. Close this window, open the Start menu, type PowerShell, choose Run as administrator, approve the Windows prompt, then paste the enrollment command again. If you cannot approve it, contact it@noovoleum.com.' }
}
function Remove-EnrollmentStage {
    [CmdletBinding()]
    param([string]$Path)
    try { Remove-Item -LiteralPath $Path -Recurse -Force } catch { Write-Warning "Could not remove protected installer staging folder $Path. Ask IT to delete it; do not reinstall solely because cleanup failed." }
}
function Test-EnrollmentInteractive {
    return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
}
function Read-EnrollmentAnswer {
    return [Console]::ReadLine()
}
function Confirm-EnrollmentAction {
    param([string]$Question)
    if (-not (Test-EnrollmentInteractive)) { throw 'An interactive console is required; no consent assumed.' }
    while ($true) {
        Write-Host ($Question + ' [Y/n]: ') -NoNewline
        $answer = Read-EnrollmentAnswer
        if ($null -eq $answer) { throw 'No input received; no consent assumed.' }
        if ($answer -ceq '' -or $answer -ceq 'y' -or $answer -ceq 'Y') { return $true }
        if ($answer -ceq 'n' -or $answer -ceq 'N') { return $false }
        Write-Host 'Please enter y or n, or press Enter for yes.'
    }
}
function Test-MiradoreEnrollment {
    param([object[]]$Records)
    $found = $false
    foreach ($record in $Records) {
        $props = $record.PSObject.Properties
        $provider = if ($props['ProviderID']) { [string]$record.ProviderID } else { '' }
        if ($provider -in @('Deploy Authority','Cloud Authority','Local Authority')) { continue }
        $urls = @()
        foreach ($name in @('DiscoveryServiceFullURL','EnrollmentServiceFullURL','PolicyServiceFullURL')) {
            if ($props[$name] -and $props[$name].Value) { $urls += [string]$props[$name].Value }
        }
        if (-not $urls.Count) { if ($provider) { return $false }; continue }
        foreach ($value in $urls) {
            $uri = $null
            if (-not [Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Port -ne 443) { return $false }
            $hostName = $uri.DnsSafeHost
            if ($hostName -ne 'online.miradore.com' -and -not $hostName.EndsWith('.online.miradore.com',[StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
        $found = $true
    }
    return $found
}
function Request-MiradoreMigration {
    param([object[]]$Records)
    if (-not (Test-MiradoreEnrollment $Records)) { throw 'Existing MDM detected. Unknown or mixed management remains blocked; contact IT.' }
    Write-Warning 'Miradore management detected. Unenrollment may remove managed certificates, applications, work data and settings. It is not a factory reset. This installer will not disconnect any Microsoft account or remove management automatically.'
    if (-not (Confirm-EnrollmentAction 'Continue to the IT-assisted Miradore migration instructions?')) { throw 'Cancelled. Management and accounts unchanged.' }
    Write-Host 'Ask IT to open Miradore > Management > Devices, select this exact device, then Lifecycle > Unenroll device > Unenroll. If the device was enrolled through Entra ID, IT must assess the Windows sign-in impact first. Do not use Retire or Wipe.'
    throw 'No unenrollment or Fleet installation was performed. Rerun this command only after IT confirms removal; Windows MDM status will be checked again.'
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
    if ($registered) {
        $records = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction Stop | ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction Stop })
        Request-MiradoreMigration $records
        throw 'Existing MDM detected. Contact IT; installation remains blocked.'
    }
}
function Get-FleetAgentState {
    # The fleetd MSI installs service "Fleet osquery" and passes settings through its Environment value.
    if (-not (Get-Service -Name 'Fleet osquery' -ErrorAction SilentlyContinue)) { return 'absent' }
    $props = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Fleet osquery' -ErrorAction Stop
    $environment = if ($props.PSObject.Properties['Environment']) { @($props.Environment) } else { @() }
    # All fleetd MSIs share one UpgradeCode: only upgrade an agent positively identified as ours.
    if ($environment -inotcontains 'ORBIT_FLEET_URL=https://mdm.noovoleum.site') { return 'unrecognized' }
    if ($environment -icontains 'ORBIT_ENABLE_SCRIPTS=true') { return 'scripts-enabled' }
    return 'scripts-disabled'
}
function Get-FleetAgentAction {
    param([string]$State)
    switch ($State) {
        'absent' { return 'install' }
        'scripts-disabled' { return 'upgrade' }
        'scripts-enabled' { return 'none' }
        default { return 'refuse' }
    }
}
function Install-NoovoleumFleet {
    Assert-NativePowerShell ([Environment]::Is64BitOperatingSystem) ([Environment]::Is64BitProcess)
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Run on Windows.' }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    Assert-EnrollmentAdministrator ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    if (-not [Environment]::UserInteractive -or (Get-Process -Id $PID).SessionId -eq 0) { throw 'Sign in interactively; do not run from a service.' }
    $action = Get-FleetAgentAction (Get-FleetAgentState)
    if ($action -eq 'none') { Write-Output 'Fleet is already installed and up to date. Nothing to do.'; return }
    if ($action -eq 'refuse') { throw 'The installed Fleet agent is not recognised as the current Noovoleum agent. Nothing changed; contact it@noovoleum.com.' }
    $upgrade = $action -eq 'upgrade'
    # An in-place agent update keeps the same Fleet device record and does not touch MDM enrollment,
    # so the new-install MDM guard (which would see Fleet's own MDM) applies only to fresh installs.
    if (-not $upgrade) { Assert-NoExistingMdm }
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        'AMD64' { $name='fleet-windows-amd64.msi'; $hash='ae414eab10c533e252a05b2b0f601baeaa5b5184f3023642898ab0de8ca4a6bc' }
        'ARM64' { $name='fleet-windows-arm64.msi'; $hash='1f90986109b68be5b5aec3bf82236c7f00ab976b490c50958226596be3654057' }
        default { throw 'Unsupported Windows architecture.' }
    }
    Write-Output 'This IT-generated MSI has no Noovoleum publisher signature. This launcher verifies its exact approved hash.'
    Write-Output 'This Fleet agent lets IT run approved maintenance scripts on this device, for example installing the remote-support agent.'
    if ($upgrade) {
        Write-Output 'Fleet is already installed. This updates it in place: same device record, MDM enrollment unchanged.'
        if (-not (Confirm-EnrollmentAction 'Update Fleet now?')) { throw 'Cancelled. Fleet left unchanged.' }
    } else {
        Write-Output 'Fleet Windows MDM can change Defender tamper protection. Proceed only on an IT-approved work device after IT has approved this security impact.'
        if (-not (Confirm-EnrollmentAction 'Install Fleet and accept the disclosed security-policy impact?')) { throw 'Cancelled.' }
    }
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
        Invoke-WebRequest -UseBasicParsing -Uri ('https://github.com/noovoleum/it-public-scripts/releases/download/enrollment-v2/' + $name) -OutFile $staged
        if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash -ine $hash) { throw 'Package hash mismatch; nothing installed. Contact IT.' }
        $process = Start-Process "$env:SystemRoot\System32\msiexec.exe" -ArgumentList @('/i',('"'+$staged+'"'),'/norestart') -Wait -PassThru
        if ($process.ExitCode -notin @(0,3010)) {
            # A major upgrade removes the old agent before installing the new one, so a failure can leave none.
            if ($upgrade) { throw "Update failed: $($process.ExitCode). The Fleet agent may be missing. Do not rerun this command; contact it@noovoleum.com." }
            throw "Installer failed: $($process.ExitCode). Contact IT."
        }
        if ($upgrade) { Write-Output 'Fleet updated. No further steps; IT verifies the next check-in.' }
        else { Write-Output 'Installed. Open Fleet Desktop > My device for MDM instructions. IT verifies fresh check-in and MDM On separately.' }
        if ($process.ExitCode -eq 3010) { Write-Output 'Windows requests a restart; save your work and arrange it yourself. No automatic restart occurs.' }
    } finally { Remove-EnrollmentStage -Path $stage }
}
if ($MyInvocation.InvocationName -ne '.') {
    try { Install-NoovoleumFleet } catch { Write-Error $_ -ErrorAction Continue; exit 1 }
}
