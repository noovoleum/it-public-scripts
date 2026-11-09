$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'install-windows.ps1')
function Assert-Throws($Action,$Pattern) {
 $message='';try { & $Action } catch { $message=$_.Exception.Message }
 if($message -notmatch $Pattern){throw "Expected refusal matching $Pattern, got $message"}
}
& {
 function Test-EnrollmentInteractive { $true }
 foreach($answer in @('','y','Y')) {
  $script:answer=$answer
  function Read-EnrollmentAnswer { $script:answer }
  if(-not (Confirm-EnrollmentAction 'Continue')){throw 'Yes input refused'}
 }
 foreach($answer in @('n','N')) {
  $script:answer=$answer
  function Read-EnrollmentAnswer { $script:answer }
  if(Confirm-EnrollmentAction 'Continue'){throw 'No input accepted'}
 }
 $script:answers=[Collections.Generic.Queue[string]]::new();$script:answers.Enqueue('garbage');$script:answers.Enqueue('y')
 function Read-EnrollmentAnswer { $script:answers.Dequeue() }
 if(-not (Confirm-EnrollmentAction 'Continue') -or $script:answers.Count){throw 'Invalid input must reprompt'}
 function Read-EnrollmentAnswer { $null }
 Assert-Throws { Confirm-EnrollmentAction 'Continue' } 'No input'
 function Read-EnrollmentAnswer { throw 'EOF' }
 Assert-Throws { Confirm-EnrollmentAction 'Continue' } 'EOF'
 function Test-EnrollmentInteractive { $false }
 Assert-Throws { Confirm-EnrollmentAction 'Continue' } 'interactive'
}
foreach($url in @('https://online.miradore.com/enrollment','https://tenant.online.miradore.com/enroll')) {
 if(-not (Test-MiradoreEnrollment @([pscustomobject]@{ProviderID='MDM';DiscoveryServiceFullURL=$url}))){throw 'Miradore not recognized'}
}
foreach($url in @('https://miradore.com.attacker.test/enroll','http://online.miradore.com/enroll','https://example.com/miradore.com','https://user:pass@online.miradore.com/','not-a-url')) {
 if(Test-MiradoreEnrollment @([pscustomobject]@{ProviderID='Miradore';DiscoveryServiceFullURL=$url})){throw 'Unknown management accepted'}
}
if(Test-MiradoreEnrollment @([pscustomobject]@{ProviderID='Miradore'})){throw 'Display name alone is not positive identification'}
if(Test-MiradoreEnrollment @([pscustomobject]@{ProviderID='MDM';DiscoveryServiceFullURL='https://online.miradore.com/';},[pscustomobject]@{ProviderID='Other MDM'})){throw 'Mixed management accepted'}
& {
 function Test-MiradoreEnrollment { $false }
 function Confirm-EnrollmentAction { throw 'Unknown MDM must not prompt' }
 Assert-Throws { Request-MiradoreMigration @() } '^Existing MDM detected'
}
& {
 function Test-MiradoreEnrollment { $true }
 function Confirm-EnrollmentAction { $false }
 Assert-Throws { Request-MiradoreMigration @() } '^Cancelled'
 function Confirm-EnrollmentAction { $true }
 Assert-Throws { Request-MiradoreMigration @() } 'No unenrollment or Fleet installation was performed'
}
Write-Output 'PASS: migration consent blank/y/n/invalid/EOF/noninteractive, Miradore identity, unknown/mixed refusal, and manual-only stop.'
