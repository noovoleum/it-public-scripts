#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Destination = $env:LAPTOP_INVENTORY_DIR,
    [ValidateSet('pass','fail','not_checked')][string]$Condition,
    [switch]$Provision
)
$ErrorActionPreference = 'Stop'

function Read-InventoryAnswer($Prompt, $Choices = 'y/n/Enter to skip') {
    Write-Host "${Prompt} [$Choices]: " -NoNewline
    [Console]::ReadLine()
}

function Read-LaptopChecks {
    $prompts = [ordered]@{
        screen = 'Screen: change brightness and check for cracks, lines or dead pixels'
        keyboard = 'Keyboard: type in Notepad and test the keys'
        trackpad = 'Trackpad: move, click and scroll'
        charger = 'Charger: plug it in and verify the charging indicator'
        camera = 'Camera: open Camera and verify the live image'
        audio = 'Audio: test the speakers and microphone'
        wifi = 'Wi-Fi: connect and load a known page'
    }
    $checks = [ordered]@{}
    foreach ($key in $prompts.Keys) {
        do {
            $answer = Read-InventoryAnswer $prompts[$key]
            if ($null -eq $answer) { throw 'Input ended before the checklist finished; nothing saved or installed.' }
            $answer = $answer.Trim()
        } until ($answer -in @('y','n',''))
        $checks[$key] = switch ($answer) { y { 'pass' } n { 'fail' } '' { 'not_checked' } }
    }
    $checks
}

function Get-LaptopCondition($Checks) {
    if ($Checks.Values -contains 'fail') { return 'fail' }
    if ($Checks.Values -contains 'not_checked') { return 'not_checked' }
    'pass'
}

function Read-InventoryCim($ClassName, $Filter) {
    $query = @{ ClassName = $ClassName; OperationTimeoutSec = 10 }
    if ($Filter) { $query.Filter = $Filter }
    try { Get-CimInstance @query -ErrorAction Stop } catch { $null }
}

function Write-InventoryFile($Directory, $Name, $Report) {
    $target = [IO.Path]::Combine($Directory, $Name)
    $temp = [IO.Path]::Combine($Directory, '.inventory-' + [guid]::NewGuid() + '.tmp')
    try {
        [IO.File]::WriteAllText($temp, $Report)
        if ([IO.File]::Exists($target)) { [IO.File]::Replace($temp, $target, [NullString]::Value) }
        else { [IO.File]::Move($temp, $target) }
    } finally {
        try { [IO.File]::Delete($temp) } catch { Write-Warning 'Could not remove inventory temporary file.' }
    }
    $target
}

function Save-LaptopInventory($LocalDirectory, $SharedDirectory, $ManualCondition, $ManualChecks) {
    $serial = ([string](Read-InventoryCim Win32_BIOS).SerialNumber).Trim().ToUpperInvariant()
    if ($serial -cnotmatch '^[A-Z0-9][A-Z0-9-]{0,99}$' -or $serial -match '^(0+|NONE|UNKNOWN|DEFAULT|NA|SYSTEMSERIALNUMBER)$') { $serial = $null }
    $device = Read-InventoryCim Win32_ComputerSystem
    $os = Read-InventoryCim Win32_OperatingSystem
    if ($os.SystemDrive -match '^[A-Z]:$') {
        $disk = Read-InventoryCim Win32_LogicalDisk "DeviceID='$($os.SystemDrive)'"
    } else { $disk = $null }
    $battery = Read-InventoryCim Win32_Battery | Select-Object -First 1
    $encryption = 'unknown'
    if ($os.SystemDrive -match '^[A-Z]:$') {
        try {
            $protection = (Get-BitLockerVolume -MountPoint $os.SystemDrive -ErrorAction Stop).ProtectionStatus
            if ($protection -eq 'On') { $encryption = 'on' }
            if ($protection -eq 'Off') { $encryption = 'off' }
        } catch { }
    }
    $report = [ordered]@{
        collected_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        serial = $serial
        hostname = [Environment]::MachineName
        manufacturer = $device.Manufacturer
        model = $device.Model
        os = $os.Caption
        os_version = if ($os.Version -and $os.BuildNumber) { "$($os.Version) (build $($os.BuildNumber))" } else { $null }
        cpu = ((Read-InventoryCim Win32_Processor).Name | Select-Object -Unique) -join ', '
        memory_bytes = $device.TotalPhysicalMemory
        disk_capacity_bytes = $disk.Size
        disk_free_bytes = $disk.FreeSpace
        battery_charge_percent = $battery.EstimatedChargeRemaining
        encryption = $encryption
        manual_condition = $ManualCondition
        manual_checks = $ManualChecks
    } | ConvertTo-Json -Depth 3

    # ponytail: latest report per serial only; use an asset system if audit history is needed.
    $name = if ($serial) { "laptop-$serial.json" } else { "laptop-unknown-$([guid]::NewGuid()).json" }
    $null = [IO.Directory]::CreateDirectory($LocalDirectory)
    $local = Write-InventoryFile $LocalDirectory $name $report
    Write-Host "Local report: $local"
    if (-not $serial) { throw 'No usable serial. Local report only; verify the serial on the laptop label.' }
    if ($SharedDirectory) {
        try {
            if (-not [IO.Directory]::Exists($SharedDirectory)) { throw 'Destination unavailable' }
            $shared = Write-InventoryFile $SharedDirectory $name $report
        } catch { throw 'Shared save not confirmed. The local report is intact. Reconnect the folder and rerun.' }
        Write-Host "Shared report: $shared"
    } else { Write-Host 'Local only: no shared folder configured.' }
}

function Invoke-LaptopInventory($LocalDirectory, $SharedDirectory, $ManualCondition, $Installer) {
    $checks = $null
    if (-not $ManualCondition) {
        $checks = Read-LaptopChecks
        $ManualCondition = Get-LaptopCondition $checks
    }
    Save-LaptopInventory $LocalDirectory $SharedDirectory $ManualCondition.ToLowerInvariant() $checks
    if ($Installer) {
        if ((Read-InventoryAnswer 'Continue to Fleet and IT remote support setup?' 'y/N') -ne 'y') {
            Write-Host 'Provisioning skipped. The inventory report is saved.'
            return
        }
        Write-Host 'Starting Fleet and Noovoleum remote support setup.'
        & $Installer
        if (-not $?) { throw 'Provisioning stopped. The inventory report is saved; follow the installer instructions.' }
        Write-Host 'Open Fleet Desktop > My device and finish any native enrollment prompts. IT must verify MDM On, fresh check-in, and the Snipe-IT record separately.'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $installer = $null
        if ($Provision) {
            if ($Condition) { throw '-Provision requires the interactive checklist; omit -Condition.' }
            if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Provisioning requires Windows.' }
            if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Open native 64-bit Windows PowerShell as administrator.' }
            $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
            if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Open native Windows PowerShell as administrator.' }
            $installer = Join-Path $PSScriptRoot 'install-windows.ps1'
            if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw 'Keep install-windows.ps1 beside this script.' }
        }
        if (-not $Condition -and [Console]::IsInputRedirected) { throw 'Use an interactive console for the checklist.' }
        $local = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Noovoleum/Laptop Inventory'
        Invoke-LaptopInventory $local $Destination $Condition $installer
    } catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}
