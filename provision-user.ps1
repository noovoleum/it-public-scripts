#Requires -Version 5.1
# Interactive provisioning of the employee's local administrator account:
# elevates via UAC (Bypass applies only to the elevated child), asks
# username / full name / password (Enter = none yet), creates the account,
# makes it administrator and lists it on the sign-in screen.
# One-liner:  irm https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/provision-user.ps1 | iex
# Checkout:   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\provision-user.ps1
$ErrorActionPreference = 'Stop'

function New-ProvisionUser {
    param(
        [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._-]{0,19}$')][string]$Username,
        [string]$FullName,
        [string]$Password,
        [string]$Description = 'Noovoleum IT provisioned account'
    )
    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        if ($Password) {
            $null = New-LocalUser -Name $Username -FullName $FullName -Description $Description -Password (ConvertTo-SecureString $Password -AsPlainText -Force) -PasswordNeverExpires
        } else {
            # Blank password: interactive sign-in only; Windows blocks blank-password network/RDP logon
            # by default, and first sign-in may still walk the employee through choosing a password.
            $null = New-LocalUser -Name $Username -FullName $FullName -Description $Description -NoPassword
        }
    }
    # Resolve the administrators group by SID; the name is localized on non-English Windows.
    $admins = (Get-LocalGroup -SID 'S-1-5-32-544').Name
    if (-not (Get-LocalGroupMember -Group $admins -Member $Username -ErrorAction SilentlyContinue)) {
        Add-LocalGroupMember -Group $admins -Member $Username
    }
    # Show local accounts as tiles on the sign-in screen. Domain/Entra-joined machines otherwise
    # show only the last signed-in user plus a typed "Other user" username+password prompt.
    $null = New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Force
    $null = New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'EnumerateLocalUsers' -Value 1 -PropertyType DWord -Force
    $policies = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $null = New-Item -Path $policies -Force
    # Keep the typed-username prompt off so the tiles stay the sign-in UI.
    $null = New-ItemProperty -Path $policies -Name 'dontdisplaylastusername' -Value 0 -PropertyType DWord -Force
    $null = New-ItemProperty -Path $policies -Name 'DontDisplayUserName' -Value 0 -PropertyType DWord -Force
    # Force-show this account per-name; NOTE the tree: Winlogon lives under 'Windows NT', not 'Windows'.
    $userList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
    $null = New-Item -Path $userList -Force
    $null = New-ItemProperty -Path $userList -Name $Username -Value 1 -PropertyType DWord -Force
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Run on Windows.' }
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            # Piped in (irm | iex) there is no file path; materialize one so the elevated child can run it.
            $scriptFile = $PSCommandPath
            if (-not $scriptFile) {
                $scriptFile = Join-Path ([IO.Path]::GetTempPath()) ('noov-provision-' + [guid]::NewGuid() + '.ps1')
                Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/provision-user.ps1' -OutFile $scriptFile -ErrorAction Stop
            }
            # Sysnative escapes a 32-bit parent so the elevated child is 64-bit.
            $ps = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
                Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
            } else {
                Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
            }
            Write-Host 'Administrator rights are needed. Approve the UAC prompt; the script continues in a new window.'
            $child = Start-Process -FilePath $ps -Verb RunAs -Wait -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $scriptFile))
            if ($scriptFile -ne $PSCommandPath) { Remove-Item -LiteralPath $scriptFile -Force -ErrorAction SilentlyContinue }
            if ($child.ExitCode -ne 0) { throw "Provisioning stopped (exit $($child.ExitCode)). See the elevated window for the reason." }
            return
        }
        if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Open native 64-bit Windows PowerShell; a 32-bit process writes the registry into the wrong view.' }
        do {
            $Username = (Read-Host 'Username for the new account').Trim()
            if ($Username -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,19}$') { Write-Host 'Invalid username: use 1-20 letters, digits, dot, dash or underscore.'; $Username = $null }
        } until ($Username)
        $FullName = (Read-Host 'Full name (Enter to use the username)').Trim()
        if (-not $FullName) { $FullName = $Username }
        $sec = Read-Host 'Password (Enter for none yet)' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        New-ProvisionUser -Username $Username -FullName $FullName -Password $Password
        $state = if ($Password) { 'password set as entered.' } else { 'no password yet; set it with the employee at handover.' }
        Write-Host "Provisioned '$Username': local administrator, listed on the sign-in screen. $state"
        Read-Host 'Done. Press Enter to close'
    } catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        if ($PSCommandPath) { Read-Host 'Finished with an error. Press Enter to close'; exit 1 }
        return
    }
}
