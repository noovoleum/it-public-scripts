# Exercise the README starting command; no network, MSI, MDM or native child.
$ErrorActionPreference='Stop'
$readme=Get-Content -Raw (Join-Path $PSScriptRoot 'README.md')
$code=[regex]::Match($readme,'(?s)```powershell\s*\n(.*?)```').Groups[1].Value.Trim()
if(-not $code){throw 'Missing Windows starting command'}
if($code -notmatch 'it-public-scripts/main/install-windows.ps1' -or $code -match 'Set-ExecutionPolicy|Invoke-Expression|Get-FileHash'){throw 'Expected stable main URL and child-only policy, without stale launcher hash'}
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($case in @('success','download-failure','child-failure')) {
 & {
  $script:stage=$null;$script:launched=$false
  function Invoke-WebRequest {
   param($Uri,$OutFile,[switch]$UseBasicParsing)
   if($Uri -ne 'https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/install-windows.ps1'){throw 'Wrong URL'}
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
  $testCode=$code.Replace('& $ps -NoProfile','Invoke-TestChild -NoProfile')
  $failed=$false
  try { & ([scriptblock]::Create($testCode)) } catch { $failed=$true }
  if(($case -eq 'success') -eq $failed){throw "Wrong outcome: $case"}
  if($script:launched -ne ($case -ne 'download-failure')){throw "Unexpected child execution: $case"}
  if(Test-Path -LiteralPath $script:stage){throw 'Staged script was not cleaned'}
 }
}
Write-Output 'PASS: stable-main Windows bootstrap syntax, child policy, download refusal, exit propagation and cleanup (native child mocked).'
