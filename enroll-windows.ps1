#Requires -Version 5.1
<# IT supplies the private MSI and its independently approved hash/publisher.
   No download credentials or enrollment secrets belong in this script. #>
[CmdletBinding()]
param(
    [string]$PackagePath,
    [string]$ExpectedSha256,
    [string]$ExpectedSignerThumbprint,
    [switch]$CheckOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-FleetPackage {
    param([string]$Path, [string]$Sha256, [string]$SignerThumbprint)
    if ($Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $SignerThumbprint -notmatch '^[a-fA-F0-9]{40}$') {
        throw 'IT must supply a SHA-256 and approved signing-certificate thumbprint.'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or [IO.Path]::GetExtension($Path) -ine '.msi') {
        throw 'Select the private .msi supplied by IT, not an HTML download/login page.'
    }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $Sha256) { throw 'Package hash mismatch. Stop and contact IT.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ine $SignerThumbprint) {
        throw 'Package publisher verification failed. Stop and contact IT.'
    }
}

function Invoke-FleetEnrollment {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Run this script on Windows.' }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Open PowerShell as administrator, then run this script again.' }
    if (-not [Environment]::UserInteractive -or (Get-Process -Id $PID).SessionId -eq 0) { throw 'Sign in interactively; do not run from a background service.' }
    if (Get-Service -Name 'Orbit' -ErrorAction SilentlyContinue) { throw 'Fleet is already installed. Contact IT to verify it; do not reinstall.' }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Enrollments') {
        $enrollments = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' | ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath })
        if (@($enrollments | Where-Object { $_.PSObject.Properties.Name -contains 'ProviderID' -and $_.ProviderID }).Count) {
            throw 'Existing device-management enrollment detected. Contact IT; this script does not migrate or replace MDM.'
        }
    }
    if (-not $PackagePath) { $PackagePath = Read-Host 'Full path to the private IT-supplied MSI' }
    if (-not $ExpectedSha256) { $ExpectedSha256 = Read-Host 'Approved SHA-256 from IT' }
    if (-not $ExpectedSignerThumbprint) { $ExpectedSignerThumbprint = Read-Host 'Approved signing-certificate thumbprint from IT' }
    if ($PackagePath -match '^[\\/]{2}' -or -not [IO.Path]::IsPathRooted($PackagePath)) { throw 'Use an absolute local package path, not a network share.' }
    # Stage under protected Program Files, then validate the exact bytes installed.
    $stage = Join-Path $env:ProgramFiles ('Noovoleum-enroll-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $stage
    try {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
            $identity = New-Object Security.Principal.SecurityIdentifier($sid)
            $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $stage -AclObject $acl
        $package = Join-Path $stage 'fleet.msi'
        Copy-Item -LiteralPath $PackagePath -Destination $package
        Assert-FleetPackage $package $ExpectedSha256 $ExpectedSignerThumbprint
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $installer.OpenDatabase($package, 0)
        $template = $database.SummaryInformation(0).Property(7).Split(';')[0]
        $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        $expectedTemplate = switch ($arch) { 'AMD64' { 'x64' } 'ARM64' { 'Arm64' } default { throw 'Unsupported Windows architecture.' } }
        if ($template -ine $expectedTemplate) { throw 'MSI architecture does not match this computer.' }
        if ($CheckOnly) { Write-Output 'Package hash, publisher and architecture verified; nothing installed.'; return }
        Write-Output 'Do not remove another MDM. IT must approve Windows MDM security-policy changes first.'
        if ((Read-Host 'Type INSTALL only if IT approved this device and its Windows security-policy changes') -cne 'INSTALL') { throw 'Cancelled; nothing installed.' }
        # No secret MSI properties, verbose log, quiet mode, or automatic restart.
        $process = Start-Process "$env:SystemRoot\System32\msiexec.exe" -ArgumentList @('/i', ('"' + $package + '"'), '/norestart') -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) { throw "Installer failed with exit code $($process.ExitCode). Contact IT; do not repeatedly reinstall." }
        Write-Output 'Installer completed. Open Fleet Desktop > My device and follow MDM instructions. IT must verify a fresh check-in and MDM On; installation alone is NOT enrollment confirmation.'
        if ($process.ExitCode -eq 3010) { Write-Output 'Windows requests a restart. Save your work and arrange it yourself; this script will not restart the device.' }
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-FleetEnrollment } catch { Write-Error $_ -ErrorAction Continue; exit 1 }
}
