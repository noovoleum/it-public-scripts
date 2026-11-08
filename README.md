# Noovoleum device enrollment

Start here: [MDM — Enroll Your Work Device](https://docs.noovoleum.site/doc/mdm-enroll-your-work-device-y9s4wsfyFV).

`install-windows.ps1` and `install-macos.sh` are credential-free online launchers. They open the appropriate **private Outline installer download** in your browser, select the package for you, verify its embedded approved SHA-256, stage the checked bytes securely and invoke the native installer. You need internet, your company Outline login, local installation permission and an IT-approved work device. Save the package to Downloads with the displayed original filename. No hashes, signing IDs, enrollment secrets or installer paths need typing.

These IT-generated packages are **not signed with a Noovoleum publisher certificate**. Exact-byte hash validation is used instead; platform consent/security prompts remain. Do not disable Gatekeeper, execution policy or antivirus. Existing Fleet/MDM is sent to IT for verification rather than automatically replaced. Windows MDM's documented Defender tamper-protection impact is disclosed before installation. No wipe, reset, automatic restart, script execution capability or custody changes are enabled by these launchers.

The employee page provides copy-paste starting commands, private package links, iPhone/iPad and Android work-profile QRs and native approval steps. Enrollment credentials and packages are never published in this repository. Do not forward private enrollment material. The native mobile page detects the platform, so the separately labelled QR images may encode the same entry URL. Fully managed Android is a separate IT-assisted new-device workflow, not a reset of an existing phone.

Source/transport/artifact checks are not a claim of successful Windows/Mac/phone enrollment. IT must verify a unique matching hardware identity, fresh agent check-in where applicable, MDM On and harmless management delivery on each pilot. The email is a draft, not automatically sent.

## Checks

```sh
bash -n install-macos.sh
shellcheck install-macos.sh
python3 test-online.py
pwsh -NoProfile -File test-online.ps1
```

Only the online `install-*` launchers are maintained; the superseded manual enrollment scripts were removed to avoid conflicting entry points. Support: it@noovoleum.com.
