Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'enroll-windows.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw $errors[0] }
. (Join-Path $PSScriptRoot 'enroll-windows.ps1')
$script:signatureCalls = 0
$script:hash = 'a' * 64
$script:status = 'Valid'
$script:thumb = 'b' * 40
function Test-Path { param($LiteralPath, $PathType) return $LiteralPath -ne 'missing.msi' }
function Get-FileHash { param($LiteralPath, $Algorithm) return @{Hash=$script:hash} }
function Get-AuthenticodeSignature { param($LiteralPath) $script:signatureCalls++; return @{Status=$script:status; SignerCertificate=@{Thumbprint=$script:thumb}} }
function Reject($Action) { $failed=$false; try { & $Action } catch { $failed=$true }; if (-not $failed) { throw 'Expected rejection' } }
Assert-FleetPackage 'fleet.msi' ('a'*64) ('b'*40)
Reject { Assert-FleetPackage 'missing.msi' ('a'*64) ('b'*40) }
Reject { Assert-FleetPackage 'login.html' ('a'*64) ('b'*40) }
Reject { Assert-FleetPackage 'fleet.msi' 'invalid' ('b'*40) }
Reject { Assert-FleetPackage 'fleet.msi' ('c'*64) ('b'*40) }
$script:status='NotSigned'; Reject { Assert-FleetPackage 'fleet.msi' ('a'*64) ('b'*40) }
$script:status='Valid'; Reject { Assert-FleetPackage 'fleet.msi' ('a'*64) ('c'*40) }
if ($script:signatureCalls -ne 3) { throw 'Unexpected signature verification count' }
Write-Output 'PASS: Windows parser and package trust rejection checks (mocked native signature APIs; no installation).'
