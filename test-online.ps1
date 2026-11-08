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
Write-Output 'PASS: online Windows parser, source loading, package pins and trust-before-install static checks; native MSI/ACL execution not exercised.'
