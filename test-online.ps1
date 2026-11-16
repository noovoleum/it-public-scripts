$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$path=Join-Path $PSScriptRoot 'install-windows.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
. $path
Assert-NativePowerShell $true $true
Assert-NativePowerShell $false $false
Assert-EnrollmentAdministrator $true
$message=''
try { Assert-EnrollmentAdministrator $false } catch { $message=$_.Exception.Message }
if($message -notmatch 'Start menu' -or $message -notmatch 'Run as administrator' -or $message -notmatch 'Nothing installed'){throw 'Non-admin refusal must give actionable elevation steps and no-install outcome'}
$rejected=$false
try { Assert-NativePowerShell $true $false } catch { $rejected=$true }
if(-not $rejected){throw 'WOW64 must be rejected before registry discovery'}
$entry=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Install-NoovoleumFleet'},$true)
if($entry.Body.EndBlock.Statements[0].Extent.Text -notmatch '^Assert-NativePowerShell '){throw 'Native-process guard must be first'}
# Validate bound package identities and the protected trust-check-before-install ordering.
$text=Get-Content -LiteralPath $path -Raw
foreach($value in @('ae414eab10c533e252a05b2b0f601baeaa5b5184f3023642898ab0de8ca4a6bc','1f90986109b68be5b5aec3bf82236c7f00ab976b490c50958226596be3654057')) {
 if($text -notmatch $value){throw 'Missing package pin'}
}
function Assert-TrustOrder($Tree) {
 $commands=$Tree.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)
 $hashCommands=@($commands | Where-Object { $_.GetCommandName() -eq 'Get-FileHash' })
 $installCommands=@($commands | Where-Object { $_.GetCommandName() -eq 'Start-Process' -and $_.Extent.Text -match 'msiexec.exe' })
 if($hashCommands.Count -ne 1 -or $installCommands.Count -ne 1 -or $hashCommands[0].Extent.StartOffset -gt $installCommands[0].Extent.StartOffset){throw 'Missing trust gate or installer precedes trust check'}
}
Assert-TrustOrder $entry
foreach($bad in @('# Get-FileHash fake comment; msiexec.exe fake comment', 'Start-Process msiexec.exe; Get-FileHash x', 'Start-Process msiexec.exe')) {
 $badTokens=$null; $badErrors=$null
 $tree=[Management.Automation.Language.Parser]::ParseInput($bad,[ref]$badTokens,[ref]$badErrors)
 $refused=$false
 try { Assert-TrustOrder $tree } catch { $refused=$true }
 if(-not $refused){throw 'Ordering check accepted missing/reordered commands'}
}
if($text -match 'FLEET_SECRET|Set-ExecutionPolicy|/quiet|/qn'){throw 'Unexpected unsafe install option'}
if($text -notmatch 'finally \{ Remove-EnrollmentStage'){throw 'Missing unconditional cleanup'}
& {
 function Remove-Item { throw 'mock file lock' }
 $warnings=@()
 $result=try { 'success' } finally { Remove-EnrollmentStage 'mock-stage' -WarningVariable warnings }
 if($result -ne 'success' -or $warnings.Count -ne 1){throw 'Cleanup changed successful result or omitted warning'}
 $message=''
 try { try { throw 'original installer failure' } finally { Remove-EnrollmentStage 'mock-stage' -WarningAction SilentlyContinue } } catch { $message=$_.Exception.Message }
 if($message -ne 'original installer failure'){throw 'Cleanup masked original installer failure'}
}
# Simulate the native DLL boundary, not the enrollment decision under test.
# Built-in authority registry entries must never trigger the old ProviderID heuristic.
& {
 Add-Type @'
using System;
public static class NoovoleumMdmRegistration {
 public static bool Registered;
 public static int Result;
 public static int IsDeviceRegisteredWithManagement(out bool registered, uint length, IntPtr userName) {
  registered = Registered;
  return Result;
 }
}
'@
 function Get-ChildItem { throw 'MDM detection must not enumerate registry authority entries' }
 [NoovoleumMdmRegistration]::Registered=$false
 [NoovoleumMdmRegistration]::Result=0
 Assert-NoExistingMdm
 [NoovoleumMdmRegistration]::Registered=$true
 function Get-ChildItem { @() }
 function Request-MiradoreMigration { throw 'Existing MDM detected. Test boundary refuses.' }
 $message=''
 try { Assert-NoExistingMdm } catch { $message=$_.Exception.Message }
 if($message -notmatch '^Existing MDM detected'){throw 'Real MDM must remain blocked'}
 foreach($registered in @($false,$true)) {
  [NoovoleumMdmRegistration]::Registered=$registered
  [NoovoleumMdmRegistration]::Result=-2147467259
  $message=''
  try { Assert-NoExistingMdm } catch { $message=$_.Exception.Message }
  if($message -notmatch '^Could not determine MDM enrollment'){throw 'API failure must fail closed regardless of returned boolean'}
 }
}
# Assert the real call path checks MDM before downloads, staging and consent.
$entryCommands=@($entry.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true))
$guard=@($entryCommands | Where-Object { $_.GetCommandName() -eq 'Assert-NoExistingMdm' })
if($guard.Count -ne 1){throw 'Installer must call the MDM guard exactly once'}
$adminGuard=@($entryCommands | Where-Object { $_.GetCommandName() -eq 'Assert-EnrollmentAdministrator' })
if($adminGuard.Count -ne 1 -or $adminGuard[0].Extent.StartOffset -gt $guard[0].Extent.StartOffset){throw 'Administrator refusal must precede MDM discovery and side effects'}
foreach($name in @('Invoke-WebRequest','New-Item','Read-Host','Start-Process')) {
 if(@($entryCommands | Where-Object { $_.GetCommandName() -eq $name -and $_.Extent.StartOffset -lt $guard[0].Extent.StartOffset }).Count){throw 'MDM guard must precede side effects and consent'}
}
if($text -match '\$existing\s*\|\s*Where-Object'){throw 'Registry ProviderID heuristic must not return'}
# Existing-agent detection: exact service name and registry path, scripts flag from the service Environment.
& {
 function Get-Service { param($Name) if($Name -ne 'Fleet osquery'){throw "Wrong service name $Name"}; $null }
 if((Get-FleetAgentState) -ne 'absent'){throw 'No Fleet service must mean absent'}
 function Get-Service { param($Name) if($Name -ne 'Fleet osquery'){throw "Wrong service name $Name"}; [pscustomobject]@{Name=$Name} }
 $url='ORBIT_FLEET_URL=https://mdm.noovoleum.site'
 foreach($case in @(@{env=@($url,'ORBIT_ENABLE_SCRIPTS=False');want='scripts-disabled'},@{env=@('ORBIT_ENABLE_SCRIPTS=True',$url);want='scripts-enabled'},@{env=@('ORBIT_FLEET_URL=https://fleet.other.example','ORBIT_ENABLE_SCRIPTS=False');want='unrecognized'},@{env=@('ORBIT_FLEET_URL=https://mdm.noovoleum.site.evil.test');want='unrecognized'},@{env=@("$url/");want='unrecognized'},@{env=$null;want='unrecognized'})) {
  $script:env=$case.env
  function Get-ItemProperty { param($LiteralPath) if($LiteralPath -ne 'HKLM:\SYSTEM\CurrentControlSet\Services\Fleet osquery'){throw "Wrong registry path $LiteralPath"}; if($null -eq $script:env){[pscustomobject]@{}}else{[pscustomobject]@{Environment=$script:env}} }
  if((Get-FleetAgentState) -ne $case.want){throw "Expected $($case.want) for $($case.env -join ',')"}
 }
}
foreach($pair in @(@('absent','install'),@('scripts-disabled','upgrade'),@('scripts-enabled','none'),@('unrecognized','refuse'),@('','refuse'))) {
 if((Get-FleetAgentAction $pair[0]) -ne $pair[1]){throw "State $($pair[0]) must map to $($pair[1])"}
}
# Drive the real entry point per action with every Windows boundary stubbed; record what it does.
foreach($case in @(
 @{action='none';     answer=$true;  mdm=0;expectPrompt=$null;exit=0;install=$false;fail=$null},
 @{action='refuse';   answer=$true;  mdm=0;expectPrompt=$null;exit=0;install=$false;fail='not recognised'},
 @{action='upgrade';  answer=$true;  mdm=0;expectPrompt='Update Fleet now?';exit=0;install=$true; fail=$null},
 @{action='upgrade';  answer=$false; mdm=0;expectPrompt='Update Fleet now?';exit=0;install=$false;fail='Cancelled. Fleet left unchanged'},
 @{action='install';  answer=$true;  mdm=1;expectPrompt='Install Fleet and accept the disclosed security-policy impact?';exit=0;install=$true;fail=$null},
 @{action='upgrade';  answer=$true;  mdm=0;expectPrompt='Update Fleet now?';exit=1603;           install=$true; fail='Do not rerun'},
 @{action='install';  answer=$true;  mdm=1;expectPrompt='Install Fleet and accept the disclosed security-policy impact?';exit=1603;install=$true;fail='^Installer failed'}
)) {
 & {
  $script:c=$case;$script:mdmCalls=0;$script:prompts=@();$script:installed=$false
  function Assert-NativePowerShell {}
  function Assert-EnrollmentAdministrator {}
  function Get-Process { [pscustomobject]@{SessionId=1} }
  function Get-FleetAgentState { 'stub' }
  function Get-FleetAgentAction { $script:c.action }
  function Assert-NoExistingMdm { $script:mdmCalls++ }
  function Confirm-EnrollmentAction { param($Question) $script:prompts+=$Question; $script:c.answer }
  function New-Item {}; function Set-Acl {}; function Invoke-WebRequest {}; function Remove-EnrollmentStage {}
  function Get-FileHash { [pscustomobject]@{Hash=$hash} }
  function Start-Process { $script:installed=$true; [pscustomobject]@{ExitCode=$(if($script:c.exit){$script:c.exit}else{0})} }
  $env:PROCESSOR_ARCHITECTURE='AMD64'; $env:PROCESSOR_ARCHITEW6432=$null; $env:ProgramFiles=[IO.Path]::GetTempPath(); $env:SystemRoot='C:\Windows'
  # Static .NET platform/identity probes cannot be stubbed; run the real body with only those lines neutralised.
  $body=$entry.Body.Extent.Text.Trim(); $body=$body.Substring(1,$body.Length-2)
  foreach($probe in @("if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Run on Windows.' }",'$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())','Assert-EnrollmentAdministrator ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))',"if (-not [Environment]::UserInteractive -or (Get-Process -Id `$PID).SessionId -eq 0) { throw 'Sign in interactively; do not run from a service.' }")) {
   if(-not $body.Contains($probe)){throw "Entry probe changed: $probe"}
   $body=$body.Replace($probe,'')
  }
  # Windows-only ACL construction for the staging folder: stub the object so the rest of the flow still runs.
  $acl='$acl = New-Object Security.AccessControl.DirectorySecurity'
  if(-not $body.Contains($acl)){throw 'Staging ACL construction changed'}
  $body=$body.Replace($acl,'$acl = [pscustomobject]@{} | Add-Member -PassThru ScriptMethod SetAccessRuleProtection {} | Add-Member -PassThru ScriptMethod AddAccessRule {}')
  function New-Object { [pscustomobject]@{} }
  $message=$null
  try { $null=& ([scriptblock]::Create($body)) } catch { $message=$_.Exception.Message }
  $label="$($case.action)/answer=$($case.answer)/exit=$($case.exit)"
  if($case.fail){ if($message -notmatch $case.fail){throw "$label expected failure '$($case.fail)', got '$message'"} } elseif($message){ throw "$label unexpected failure: $message" }
  if($script:mdmCalls -ne $case.mdm){throw "$label MDM guard calls $($script:mdmCalls), expected $($case.mdm)"}
  if($script:installed -ne $case.install){throw "$label installer ran=$($script:installed), expected $($case.install)"}
  $wantPrompts=@($case.expectPrompt | Where-Object {$_})
  if(($script:prompts -join '|') -ne ($wantPrompts -join '|')){throw "$label prompts '$($script:prompts -join '|')', expected '$($wantPrompts -join '|')'"}
 }
}
if($text -match "Get-Service\s+-Name\s+'?Orbit"){throw 'Fleet service is named "Fleet osquery", not Orbit'}
if($text -notmatch 'releases/download/enrollment-v2/'){throw 'Launcher must download the scripts-enabled release'}
if($text -notmatch "-ArgumentList @\('/i',\('`"'\+\`$staged\+'`"'\),'/norestart'\)"){throw 'msiexec arguments changed (no /quiet, /passive or extra properties)'}
if($text -notmatch '\.Hash -ine \$hash\) \{ throw'){throw 'Hash mismatch must refuse installation'}
Write-Output 'PASS: Windows parser, trust ordering, native-process and MDM refusal/error decision regressions; actual Windows DLL, MSI and ACL execution not exercised.'
