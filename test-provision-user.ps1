# Runs on PowerShell 5.1+; local account and registry cmdlets are the Windows boundary.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/provision-user.ps1"

$script:users = [Collections.ArrayList]@()
$script:created = @{}
$script:members = [Collections.ArrayList]@()
$script:groupAdds = [Collections.ArrayList]@()
$script:registry = @{}

function Get-LocalUser { param($Name, $ErrorAction) if ($script:users -contains $Name) { [pscustomobject]@{ Name = $Name } } else { $null } }
function New-LocalUser {
    param($Name, $FullName, $Description, $Password, [switch]$NoPassword, [switch]$PasswordNeverExpires)
    if ([bool]$Password -eq [bool]$NoPassword) { throw 'Exactly one of Password/NoPassword must be set' }
    if ($script:users -contains $Name) { throw "User $Name already exists" }
    $null = $script:users.Add($Name)
    $script:created[$Name] = @{ Password = $Password; NoPassword = [bool]$NoPassword; NoExpires = [bool]$PasswordNeverExpires }
    [pscustomobject]@{ Name = $Name }
}
function Get-LocalGroup { param($SID) if ($SID -ne 'S-1-5-32-544') { throw 'Admin group must be resolved by SID' }; [pscustomobject]@{ Name = 'Administrators' } }
function Get-LocalGroupMember {
    [CmdletBinding()]
    param($Group, $Member)
    if ($Group -ne 'Administrators') { throw 'Wrong group' }
    if ($script:members -contains $Member) { [pscustomobject]@{ Name = $Member } } else { Write-Error "$Member is not in $Group" }
}
function Add-LocalGroupMember { param($Group, $Member) if ($Group -ne 'Administrators') { throw 'Wrong group' }; $null = $script:members.Add($Member); $null = $script:groupAdds.Add($Member) }
function New-Item { param($Path, [switch]$Force) }
function New-ItemProperty {
    param($Path, $Name, $Value, $PropertyType, [switch]$Force)
    if ($PropertyType -ne 'DWord') { throw 'Only DWord values are expected here' }
    $script:registry["$Path|$Name"] = @{ Value = $Value }
}

$enumUsers = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System|EnumerateLocalUsers'
$policies = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
# Winlogon lives under 'Windows NT' — the tree without 'NT' is never read by the sign-in UI.
$userList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'

# 1. Passwordless provisioning makes the account a listed admin on the sign-in screen.
New-ProvisionUser -Username 'jdoe' -FullName 'Jane Doe' -Password '' -Description 'IT'
if ($script:users.Count -ne 1 -or -not $script:created['jdoe'].NoPassword -or $script:created['jdoe'].Password) { throw 'Passwordless account was not created correctly' }
if ($script:groupAdds.Count -ne 1 -or $script:groupAdds[0] -ne 'jdoe') { throw 'Account was not made administrator' }
if ($script:registry[$enumUsers].Value -ne 1) { throw 'EnumerateLocalUsers policy not enabled' }
if ($script:registry["$policies|dontdisplaylastusername"].Value -ne 0 -or $script:registry["$policies|DontDisplayUserName"].Value -ne 0) { throw 'Typed-username prompt policies not cleared' }
if ($script:registry["$userList|jdoe"].Value -ne 1) { throw 'Sign-in screen listing missing or under the wrong tree' }

# 2. Rerun fills only what is missing.
New-ProvisionUser -Username 'jdoe' -FullName 'Jane Doe' -Password ''
if ($script:users.Count -ne 1 -or $script:groupAdds.Count -ne 1 -or $script:registry.Count -ne 4) { throw 'Rerun duplicated work' }

# 3. Password path stores a real secret that will not expire on the employee.
New-ProvisionUser -Username 'asmith' -Password 'temp123'
if (-not $script:created['asmith'].Password -or $script:created['asmith'].NoPassword -or -not $script:created['asmith'].NoExpires) { throw 'Password was not set or was left expiring' }

# 4. Invalid usernames are rejected before anything runs.
$failed = $false
try { New-ProvisionUser -Username 'bad name' } catch { $failed = $true }
if (-not $failed -or $script:users.Count -ne 2) { throw 'Invalid username was not rejected' }

Write-Host 'test-provision-user: OK'
