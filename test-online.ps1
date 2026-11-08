$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$path=Join-Path $PSScriptRoot 'install-windows.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
. $path
Assert-NativePowerShell $true $true
Assert-NativePowerShell $false $false
$rejected=$false
try { Assert-NativePowerShell $true $false } catch { $rejected=$true }
if(-not $rejected){throw 'WOW64 must be rejected before registry discovery'}
$entry=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Install-NoovoleumFleet'},$true)
if($entry.Body.EndBlock.Statements[0].Extent.Text -notmatch '^Assert-NativePowerShell '){throw 'Native-process guard must be first'}
# Validate bound package identities and the protected trust-check-before-install ordering.
$text=Get-Content -LiteralPath $path -Raw
foreach($value in @('52569b1cdbbda4441bda63794f086a0ce63344dfb7d3c91c6967572b59cd6b22','dea536c3cf567b0919ef7a3315c621fdc6670327a7507e31fee86c5a1f2e2bfd')) {
 if($text -notmatch $value){throw 'Missing package pin'}
}
if($text.IndexOf('Get-FileHash') -gt $text.IndexOf('msiexec.exe')){throw 'Installer precedes trust check'}
if($text -match 'FLEET_SECRET|Set-ExecutionPolicy|/quiet|/qn'){throw 'Unexpected unsafe install option'}
if($text -notmatch 'finally \{ Remove-Item'){throw 'Missing unconditional cleanup'}
Write-Output 'PASS: online Windows parser, source loading, package pins and trust-before-install static checks; native MSI/ACL execution not exercised.'
