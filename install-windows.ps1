#Requires -Version 5.1
# Credential-free launcher. Private packages require company Outline browser login.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Install-NoovoleumFleet {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Run on Windows.' }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Open PowerShell as administrator and run the command again.' }
    if (-not [Environment]::UserInteractive -or (Get-Process -Id $PID).SessionId -eq 0) { throw 'Sign in interactively; do not run from a service.' }
    if (Get-Service -Name Orbit -ErrorAction SilentlyContinue) { Write-Output 'Fleet is already installed. Contact IT to verify it; no reinstall performed.'; return }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Enrollments') {
        $existing = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' | ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath })
        if (@($existing | Where-Object { $_.PSObject.Properties.Name -contains 'ProviderID' -and $_.ProviderID }).Count) { throw 'Existing MDM detected. Contact IT; no migration or replacement is performed.' }
    }
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        'AMD64' { $name='fleet-windows-amd64.msi'; $hash='52569b1cdbbda4441bda63794f086a0ce63344dfb7d3c91c6967572b59cd6b22'; $attachment='dc237b1a-7455-402a-b92f-01ee5bf8408d' }
        'ARM64' { $name='fleet-windows-arm64.msi'; $hash='dea536c3cf567b0919ef7a3315c621fdc6670327a7507e31fee86c5a1f2e2bfd'; $attachment='a731e2ea-7cbd-4ad9-9a82-84959dc3ad6b' }
        default { throw 'Unsupported Windows architecture.' }
    }
    Write-Output 'The browser will download the Noovoleum Fleet installer. Sign in to company Outline if asked, and save it in Downloads.'
    Start-Process ('https://docs.noovoleum.site/api/attachments.redirect?id=' + $attachment)
    $null = Read-Host 'Press Enter after the browser download finishes'
    $package = Join-Path $HOME ('Downloads\' + $name)
    if (-not (Test-Path -LiteralPath $package -PathType Leaf)) { throw "Expected Downloads\$name. Move the downloaded file there and run again." }
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
        Copy-Item -LiteralPath $package -Destination $staged
        if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash -ine $hash) { throw 'Package hash mismatch; nothing installed. Contact IT.' }
        $process = Start-Process "$env:SystemRoot\System32\msiexec.exe" -ArgumentList @('/i',('"'+$staged+'"'),'/norestart') -Wait -PassThru
        if ($process.ExitCode -notin @(0,3010)) { throw "Installer failed: $($process.ExitCode). Contact IT." }
        Write-Output 'Installed. Open Fleet Desktop > My device for MDM instructions. IT verifies fresh check-in and MDM On separately.'
        if ($process.ExitCode -eq 3010) { Write-Output 'Windows requests a restart; save your work and arrange it yourself. No automatic restart occurs.' }
    } finally { Remove-Item -LiteralPath $stage -Recurse -Force }
}
if ($MyInvocation.InvocationName -ne '.') {
    try { Install-NoovoleumFleet } catch { Write-Error $_ -ErrorAction Continue; exit 1 }
}
