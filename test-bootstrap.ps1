# Exercise the exact short README command and bootstrap; no network/native child.
$ErrorActionPreference='Stop'
$readme=Get-Content -Raw (Join-Path $PSScriptRoot 'README.md')
$code=[regex]::Match($readme,'(?s)```powershell\s*\n(.*?)```').Groups[1].Value.Trim()
if($code -ne 'irm https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/bootstrap-windows.ps1 | iex'){throw 'Expected short Windows bootstrap command'}
$bootstrap=Get-Content -Raw (Join-Path $PSScriptRoot 'bootstrap-windows.ps1')
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseInput($bootstrap,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
if($bootstrap -match 'Set-ExecutionPolicy|Invoke-Expression|Get-FileHash'){throw 'Unexpected persistent policy or stale launcher hash'}
foreach($case in @('success','bootstrap-download-failure','download-failure','child-failure')) {
 & {
  $script:stage=$null;$script:launched=$false
  function Invoke-RestMethod {
   param($Uri)
   if($Uri -ne 'https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/bootstrap-windows.ps1'){throw 'Wrong bootstrap URL'}
   if($case -eq 'bootstrap-download-failure'){throw 'network failure'}
   $bootstrap.Replace('& $ps -NoProfile','Invoke-TestChild -NoProfile')
  }
  function Invoke-WebRequest {
   param($Uri,$OutFile,[switch]$UseBasicParsing)
   if($Uri -ne 'https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/install-windows.ps1'){throw 'Wrong installer URL'}
   $script:stage=$OutFile
   [IO.File]::WriteAllText($OutFile,'# harmless fixture')
   if($case -eq 'download-failure'){throw 'network failure'}
  }
  function Invoke-TestChild {
   param([switch]$NoProfile,[string]$ExecutionPolicy,[string]$File)
   if(-not $NoProfile -or $ExecutionPolicy -ne 'Bypass' -or -not (Test-Path -LiteralPath $File)){throw 'Wrong child contract'}
   $script:launched=$true
   $global:LASTEXITCODE=if($case -eq 'child-failure'){7}else{0}
  }
  $failed=$false
  try { & ([scriptblock]::Create($code)) } catch { $failed=$true }
  if(($case -eq 'success') -eq $failed){throw "Wrong outcome: $case"}
  if($script:launched -ne ($case -in @('success','child-failure'))){throw "Unexpected child execution: $case"}
  if($script:stage -and (Test-Path -LiteralPath $script:stage)){throw 'Staged script was not cleaned'}
 }
}
Write-Output 'PASS: short Windows command, bootstrap/download refusal, child-only policy, exit propagation and cleanup (native child mocked).'
