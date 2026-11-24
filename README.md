# Noovoleum device enrollment

Start here: [MDM — Enroll Your Work Device](https://docs.noovoleum.site/doc/mdm-enroll-your-work-device-y9s4wsfyFV).

`install-windows.ps1` and `install-macos.sh` automatically download the appropriate **public GitHub release installer**, verify its pinned SHA-256, stage the checked bytes securely and invoke the native installer. No browser, login, Downloads-folder selection or manual trust values are required. You need internet, local installation permission and an IT-approved work device. Native consent prompts remain.

These IT-generated packages are **not signed with a Noovoleum publisher certificate**. Exact-byte hash validation is used instead; platform consent/security prompts remain. Do not disable Gatekeeper or antivirus, or change persistent execution-policy settings. The approved starting command uses an installer-only PowerShell child process with `-ExecutionPolicy Bypass`; organization-enforced restrictions still apply. Other existing MDM is sent to IT rather than replaced; an existing Noovoleum Fleet install is completed in place. Windows MDM's documented Defender tamper-protection impact is disclosed before installation. No wipe, reset, automatic restart or custody changes are enabled by these launchers. The Fleet agent allows IT-run maintenance scripts, and the launchers install Noovoleum remote support.

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

## Rerunning on an already-enrolled device

The same command is safe to rerun on any laptop and finishes whatever is missing. Both launchers also install **Noovoleum remote support** (MeshCentral agent for `remote.noovoleum.site`, group "Fleet managed", SHA-256 pinned). IT screen sharing asks the employee for approval each time; IT file or terminal access shows a notification.

| Laptop state | Windows | Mac |
|---|---|---|
| Nothing installed | Fleet (MDM check, consent) + remote support | Fleet (MDM check, consent) + remote support |
| Noovoleum Fleet, scripts off (`enrollment-v1`) | In-place update to `enrollment-v2` + remote support | n/a (Mac scripts are on via MDM) |
| Noovoleum Fleet, remote support missing | Remote support only | Remote support only |
| Everything present | Nothing to do | Nothing to do |
| Fleet for another server | Refused, nothing changed | Refused, nothing changed |

Updating our own agent never touches MDM enrollment and keeps the same Fleet device record, so the new-install MDM check runs only on fresh installs. A failed Windows agent update can leave no agent (the MSI major upgrade removes the old one first): the message then says not to rerun and to contact IT, who reinstall `enrollment-v2` with `msiexec /i` (enrollment and node key survive, so the same host record returns). On Mac, IT screen sharing also needs "meshagent" allowed under System Settings > Privacy & Security > Screen & System Audio Recording and Accessibility; the launcher prints this.

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

Only the online `install-*` launchers are maintained for enrollment; the superseded manual enrollment scripts were removed to avoid conflicting entry points. Support: it@noovoleum.com.

## Fleet enrollment and Snipe-IT inventory

For IT-approved laptops, run the existing [Windows or Mac enrollment command](#stable-starting-commands) and complete the native prompts in Fleet Desktop. No separate inventory upload or Snipe-IT login is needed. IT verifies a fresh Fleet check-in and **MDM On**; an installed agent alone does not prove MDM enrollment finished.

IT verifies that Fleet inventory reconciles with the asset register. Enrollment does not assign custody; see the [IT bench runbook](https://docs.noovoleum.site/doc/laptop-bench-setup-hardware-checks-and-fleet-enrollment-wHzg1pFaX8) for the internal verification steps.

## IT bench setup: checklist and provisioning in one run

Get the inventory and install scripts for your platform from the same trusted checkout; keep them in the same folder. Use an IT-approved laptop and a private inventory share. Replace the example paths below with your actual share. Run Windows from native 64-bit administrator PowerShell, or macOS 12+ from ordinary Terminal after mounting the share in Finder.

```powershell
powershell.exe -NoProfile -File .\inventory-windows.ps1 -Provision -Destination '\\fileserver\IT\Laptop Inventory'
```

```bash
bash ./inventory-macos.sh --provision '/Volumes/IT/Laptop Inventory'
```

The script guides the screen, keyboard, trackpad, charger, camera, audio and Wi-Fi checks. Enter `y` for pass, `n` for fail, or Enter to skip each one. It also reads the serial, make/model, OS, CPU, RAM, disk, battery and encryption status when available. These are bench checks, not automated hardware diagnostics or proof of MDM enrollment.

The report is saved locally and then to the share as `laptop-<serial>.json` before the existing Fleet and IT remote-support installer starts. A failed hardware check is recorded, not erased or treated as a pass. Type `y` to start provisioning; Enter skips it. The installer still asks for its own approval. If the serial is unusable or the configured share fails, the report stays local and provisioning does not start. With no destination the report stays local; set `LAPTOP_INVENTORY_DIR` to use a default share. A later installer failure leaves the report intact.

Finish any native enrollment prompts. IT verifies MDM On, fresh Fleet check-in and the matching Snipe-IT record. The manual checklist stays separate from the asset register. IT setup here means the existing remote-support agent; no local admin account is created and no API key is needed on the laptop.

For inventory only, omit `-Provision` or `--provision`. Checks: `bash test-laptop-inventory-macos.sh` (Mac with Python 3 for the test only) and `pwsh -NoProfile -File test-laptop-inventory.ps1` (simulated Windows hardware and installer).
