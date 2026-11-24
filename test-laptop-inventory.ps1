# Runs on PowerShell 5.1+; CIM is the Windows hardware boundary.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/inventory-windows.ps1"

function Get-CimInstance {
    param($ClassName, $Filter, $OperationTimeoutSec)
    switch ($ClassName) {
        Win32_BIOS { @{ SerialNumber = $serial } }
        Win32_ComputerSystem { @{ Manufacturer = 'Example'; Model = 'Laptop'; TotalPhysicalMemory = 17179869184 } }
        Win32_OperatingSystem { @{ Caption = 'Windows'; Version = '10.0'; BuildNumber = '22631'; SystemDrive = 'C:' } }
        Win32_Processor { @{ Name = 'Example CPU' } }
        Win32_LogicalDisk { if ($Filter -ne "DeviceID='C:'") { throw 'Wrong disk' }; @{ Size = 512000000000; FreeSpace = 256000000000 } }
        Win32_Battery { throw 'Access denied' }
        default { throw 'Unexpected class' }
    }
}
function Get-BitLockerVolume { throw 'Access denied' }

$root = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
try {
    $shared = Join-Path $root 'shared'
    $local = Join-Path $root 'local'
    $null = [IO.Directory]::CreateDirectory($shared)
    $serial = ' abc-123 '
    Save-LaptopInventory $local $shared 'pass'
    $script:answers = [Collections.Queue]::new()
    foreach ($answer in @('invalid','y','n','','y','y','y','y')) { $script:answers.Enqueue($answer) }
    function Read-InventoryAnswer($Prompt) { $script:answers.Dequeue() }
    $checks = Read-LaptopChecks
    if ($script:answers.Count -ne 0 -or $checks.screen -ne 'pass' -or $checks.keyboard -ne 'fail' -or $checks.trackpad -ne 'not_checked') { throw 'Individual answers were not recorded' }
    Save-LaptopInventory $local $shared (Get-LaptopCondition $checks) $checks
    if ((Get-LaptopCondition @{ screen = 'pass'; charger = 'not_checked' }) -ne 'not_checked') { throw 'A partial check was marked pass' }
    $reports = @(Get-ChildItem -LiteralPath $shared)
    if ($reports.Count -ne 1 -or $reports[0].Name -ne 'laptop-ABC-123.json') { throw 'Rerun did not replace one report by serial' }
    $row = Get-Content -Raw -LiteralPath $reports[0].FullName | ConvertFrom-Json
    if ($row.serial -ne 'ABC-123' -or $row.manual_condition -ne 'fail' -or $row.battery_charge_percent -ne $null -or $row.encryption -ne 'unknown' -or $row.disk_capacity_bytes -ne 512000000000) { throw 'Incorrect report or false pass on unreadable hardware' }
    $failed = $false
    try { Save-LaptopInventory $local (Join-Path $root 'missing') 'pass' } catch {
        if ($_.Exception.Message -notlike 'Shared save not confirmed*') { throw }
        $failed = $true
    }
    if (-not $failed -or (Get-Content -Raw -LiteralPath (Join-Path $local $reports[0].Name) | ConvertFrom-Json).manual_condition -ne 'pass') { throw 'Failed shared write lost the local record or claimed success' }
    $installer = Join-Path $root 'install-windows.ps1'
    [IO.File]::WriteAllText($installer, @'
$before = Get-Content -Raw -LiteralPath (Join-Path $SharedDirectory 'laptop-ABC-123.json') | ConvertFrom-Json
if ($before.manual_checks.trackpad -ne 'pass') { throw 'Provisioning started before the detailed report was saved' }
if ($installerFails) { exit 7 }
'@)
    foreach ($answer in @('y','n','y','y','y','y','y','')) { $script:answers.Enqueue($answer) }
    Invoke-LaptopInventory $local $shared '' { throw 'Blank confirmation started provisioning' }
    if ($script:answers.Count -ne 0) { throw 'Missing provisioning confirmation' }
    foreach ($installerFails in @($false, $true)) {
        foreach ($answer in @('y','n','y','y','y','y','y','y')) { $script:answers.Enqueue($answer) }
        $failed = $false
        try { Invoke-LaptopInventory $local $shared '' $installer } catch {
            if ($_.Exception.Message -notlike 'Provisioning stopped*') { throw }
            $failed = $true
        }
        if ($failed -ne $installerFails) { throw 'Wrong provisioning outcome' }
    }
    $serial = 'To Be Filled By O.E.M.'
    $failed = $false
    try { Save-LaptopInventory $local $shared 'not_checked' } catch {
        if ($_.Exception.Message -notlike 'No usable serial*') { throw }
        $failed = $true
    }
    if (-not $failed -or @(Get-ChildItem -LiteralPath $shared).Count -ne 1 -or @(Get-ChildItem -LiteralPath $local -Filter 'laptop-unknown-*.json').Count -ne 1) { throw 'Placeholder serial entered the shared inventory or lost the local record' }
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
'PASS: Windows report, serial replacement, unknown fields, and local fallback.'
