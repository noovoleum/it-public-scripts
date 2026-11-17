# Noovoleum device enrollment

Start here: [MDM — Enroll Your Work Device](https://docs.noovoleum.site/doc/mdm-enroll-your-work-device-y9s4wsfyFV).

`install-windows.ps1` and `install-macos.sh` automatically download the appropriate **public GitHub release installer**, verify its pinned SHA-256, stage the checked bytes securely and invoke the native installer. No browser, login, Downloads-folder selection or manual trust values are required. You need internet, local installation permission and an IT-approved work device. Native consent prompts remain.

These IT-generated packages are **not signed with a Noovoleum publisher certificate**. Exact-byte hash validation is used instead; platform consent/security prompts remain. Do not disable Gatekeeper or antivirus, or change persistent execution-policy settings. The approved starting command uses an installer-only PowerShell child process with `-ExecutionPolicy Bypass`; organization-enforced restrictions still apply. Other existing MDM is sent to IT rather than replaced; an existing Noovoleum Fleet agent on Windows is updated in place. Windows MDM's documented Defender tamper-protection impact is disclosed before installation. No wipe, reset, automatic restart or custody changes are enabled by these launchers. The Windows agent allows IT-run maintenance scripts (for example, installing the remote-support agent).

The employee page provides copy-paste starting commands, public package links, iPhone/iPad and Android work-profile QRs and native approval steps. The owner approved public installer distribution: packages contain an extractable reusable enrollment key, not an administrator token. Anyone can register a device with that key; enrollment must never be treated as company-access entitlement. Do not distribute sensitive configuration or credentials merely because a device is enrolled. The native mobile page detects the platform, so the separately labelled QR images may encode the same entry URL. Fully managed Android is a separate IT-assisted new-device workflow, not a reset of an existing phone.

Source/transport/artifact checks are not a claim of successful Windows/Mac/phone enrollment. IT must verify a unique matching hardware identity, fresh agent check-in where applicable, MDM On and harmless management delivery on each pilot. The email is a draft, not automatically sent.

## Stable starting commands

These commands deliberately fetch the current script on `main` over HTTPS, not a frozen script hash. Future merged launcher updates use the same command. This trusts GitHub and repository write access; only the downloaded **installer packages** remain SHA-256 pinned inside the scripts. The short commands execute only a small bootstrap this way. It downloads the full installer launcher to a temporary file before execution and removes it afterward. The Mac bootstrap reconnects stdin to `/dev/tty` so `[Y/n]` reads the keyboard rather than downloaded code; without a terminal it fails closed. The Windows bootstrap runs the launcher in a native PowerShell child with process-only Bypass and propagates its failure. Do not pipe the installer launcher itself into a shell.

**Windows — run in administrator PowerShell:**

```powershell
irm https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/bootstrap-windows.ps1 | iex
```

**Mac — run in ordinary Terminal, without sudo:**

```bash
curl -fsSL https://raw.githubusercontent.com/noovoleum/it-public-scripts/main/bootstrap-macos.sh | /bin/bash
```

## Updating an existing Windows agent

Rerunning the same Windows command on a laptop that already has Fleet updates the agent in place to the `enrollment-v2` package. That package is identical to v1 except that IT script execution is turned on. The MSI major upgrade keeps the same Fleet device record and does not touch MDM enrollment, so the new-install MDM check is skipped on this path. An agent that already has scripts enabled is left alone. Fleet Desktop shows the device again after its next check-in, with no further steps for the employee.

## Windows MDM detection

The launcher queries Windows' [IsDeviceRegisteredWithManagement API](https://learn.microsoft.com/en-us/windows/win32/api/mdmregistration/nf-mdmregistration-isdeviceregisteredwithmanagement), not arbitrary enrollment registry `ProviderID` values. Built-in Deploy / Cloud / Local Authority records and work-account registration alone are not proof of MDM enrollment. Actual MDM registration blocks installation; a failed status query also stops installation. Do not disconnect Microsoft accounts or delete registry entries to bypass this check.

## Miradore migration and administrator prompt

Only positively identified Miradore HTTPS management endpoints receive a migration prompt. Unknown or mixed MDM remains blocked. The warning explains that managed certificates, apps, work data and settings may be removed. At `[Y/n]`, Enter/y/Y means yes, n/N cancels, invalid input re-prompts, and EOF or noninteractive input never implies consent.

Yes opens instructions, **not automatic removal**: Windows requires IT to select the exact device in Miradore and use Lifecycle > Unenroll device > Unenroll (not Retire/Wipe). IT must assess Entra-enrolled devices' sign-in impact first. Mac instructions target only the Miradore MDM profile through native Settings; blocked removal/ADE requires IT. Both paths stop without installing Fleet; rerun after approved removal so native MDM status is checked again. No account disconnection, registry deletion, profile-removal command, reset or security-prompt bypass is used. Mobile enrollment links are unchanged; this migration prompt covers desktop launchers only.

Windows checks administrator privileges before MDM discovery, consent, package download or installation. A non-elevated session stops with Start menu > PowerShell > Run as administrator instructions, the no-install outcome and the IT contact. No automatic elevation is attempted.

## Microsoft 365 licenses → Snipe-IT (IT admin)

`sync-m365-licenses-snipeit.py` mirrors M365 license assignments into Snipe-IT: one license per paid SKU (bound by SKU ID in *Order Number*), seats = purchased units, one seat checked out per Snipe-IT user holding that SKU. Microsoft is authoritative: seats of users who lost the SKU are checked in. It never creates or deletes Snipe-IT users and leaves asset-assigned seats alone; M365 users it cannot match (email, then username = UPN prefix, then unique full name) are listed for IT. Free/trial SKUs (10,000+ units) are skipped unless named with `--sku`.

```sh
export SNIPEIT_TOKEN=… CF_ACCESS_CLIENT_ID=… CF_ACCESS_CLIENT_SECRET=…   # from IT's credential store
python3 sync-m365-licenses-snipeit.py           # dry run: prints the plan
python3 sync-m365-licenses-snipeit.py --apply   # writes
```

Graph access uses a signed-in `m365` CLI (Organization.Read.All, User.Read.All), or `GRAPH_TOKEN`. No credentials live in this repository.

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
python3 test-m365-license-sync.py
```

These include mocked Windows native boundaries and Mac PTY consent; native Windows PowerShell 5.1, MSI/ACL installation and real-device Miradore unenrollment remain pilot acceptance gates.

Never unenroll a live device as a test.

Only the online `install-*` launchers are maintained; the superseded manual enrollment scripts were removed to avoid conflicting entry points. Support: it@noovoleum.com.
