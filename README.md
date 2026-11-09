# Noovoleum device enrollment

Start here: [MDM — Enroll Your Work Device](https://docs.noovoleum.site/doc/mdm-enroll-your-work-device-y9s4wsfyFV).

`install-windows.ps1` and `install-macos.sh` automatically download the appropriate **public GitHub release installer**, verify its pinned SHA-256, stage the checked bytes securely and invoke the native installer. No browser, login, Downloads-folder selection or manual trust values are required. You need internet, local installation permission and an IT-approved work device. Native consent prompts remain.

These IT-generated packages are **not signed with a Noovoleum publisher certificate**. Exact-byte hash validation is used instead; platform consent/security prompts remain. Do not disable Gatekeeper or antivirus, or change persistent execution-policy settings. The approved starting command uses an installer-only PowerShell child process with `-ExecutionPolicy Bypass`; organization-enforced restrictions still apply. Existing Fleet/MDM is sent to IT for verification rather than automatically replaced. Windows MDM's documented Defender tamper-protection impact is disclosed before installation. No wipe, reset, automatic restart, script execution capability or custody changes are enabled by these launchers.

The employee page provides copy-paste starting commands, public package links, iPhone/iPad and Android work-profile QRs and native approval steps. The owner approved public installer distribution: packages contain an extractable reusable enrollment key, not an administrator token. Anyone can register a device with that key; enrollment must never be treated as company-access entitlement. Do not distribute sensitive configuration or credentials merely because a device is enrolled. The native mobile page detects the platform, so the separately labelled QR images may encode the same entry URL. Fully managed Android is a separate IT-assisted new-device workflow, not a reset of an existing phone.

Source/transport/artifact checks are not a claim of successful Windows/Mac/phone enrollment. IT must verify a unique matching hardware identity, fresh agent check-in where applicable, MDM On and harmless management delivery on each pilot. The email is a draft, not automatically sent.

## Stable starting commands

These commands deliberately fetch the current script on `main` over HTTPS, not a frozen script hash. Future merged launcher updates use the same command. This trusts GitHub and repository write access; only the downloaded **installer packages** remain SHA-256 pinned inside the scripts. Do not replace this with pipe-to-shell or `Invoke-Expression`: staging keeps consent input interactive and avoids executing a partially downloaded response.

**Windows — run in administrator PowerShell:**

```powershell
$p=Join-Path $env:TEMP ('noov-enroll-'+[guid]::NewGuid()+'.ps1'); try { Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/install-windows.ps1' -OutFile $p -ErrorAction Stop; $ps=if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe' } else { Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe' }; & $ps -NoProfile -ExecutionPolicy Bypass -File $p; if ($LASTEXITCODE -ne 0) { throw "Enrollment stopped (exit $LASTEXITCODE). Contact IT with the displayed error." } } finally { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
```

**Mac — run in ordinary Terminal, without sudo:**

```bash
(p=$(mktemp) && trap 'rm -f "$p"' EXIT && curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' 'https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/install-macos.sh' -o "$p" && /bin/bash "$p")
```

## Windows MDM detection

The launcher queries Windows' [IsDeviceRegisteredWithManagement API](https://learn.microsoft.com/en-us/windows/win32/api/mdmregistration/nf-mdmregistration-isdeviceregisteredwithmanagement), not arbitrary enrollment registry `ProviderID` values. Built-in Deploy / Cloud / Local Authority records and work-account registration alone are not proof of MDM enrollment. Actual MDM registration blocks installation; a failed status query also stops installation. Do not disconnect Microsoft accounts or delete registry entries to bypass this check.

## Miradore migration and administrator prompt

Only positively identified Miradore HTTPS management endpoints receive a migration prompt. Unknown or mixed MDM remains blocked. The warning explains that managed certificates, apps, work data and settings may be removed. At `[Y/n]`, Enter/y/Y means yes, n/N cancels, invalid input re-prompts, and EOF or noninteractive input never implies consent.

Yes opens instructions, **not automatic removal**: Windows requires IT to select the exact device in Miradore and use Lifecycle > Unenroll device > Unenroll (not Retire/Wipe). IT must assess Entra-enrolled devices' sign-in impact first. Mac instructions target only the Miradore MDM profile through native Settings; blocked removal/ADE requires IT. Both paths stop without installing Fleet; rerun after approved removal so native MDM status is checked again. No account disconnection, registry deletion, profile-removal command, reset or security-prompt bypass is used. Mobile enrollment links are unchanged; this migration prompt covers desktop launchers only.

Windows checks administrator privileges before MDM discovery, consent, package download or installation. A non-elevated session stops with Start menu > PowerShell > Run as administrator instructions, the no-install outcome and the IT contact. No automatic elevation is attempted.

## Checks

```sh
bash -n install-macos.sh
shellcheck install-macos.sh
python3 test-online.py
python3 test-migration.py
pwsh -NoProfile -File test-online.ps1
pwsh -NoProfile -File test-migration.ps1
python3 test-bootstrap.py
pwsh -NoProfile -File test-bootstrap.ps1
```

These include mocked Windows native boundaries and Mac PTY consent; native Windows PowerShell 5.1, MSI/ACL installation and real-device Miradore unenrollment remain pilot acceptance gates.

Never unenroll a live device as a test.

Only the online `install-*` launchers are maintained; the superseded manual enrollment scripts were removed to avoid conflicting entry points. Support: it@noovoleum.com.
