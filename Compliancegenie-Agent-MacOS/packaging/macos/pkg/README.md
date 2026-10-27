# ComplianceGenie Agent: macOS installer (.pkg)

The macOS equivalent of the Windows MSI. Clients double-click a `.pkg`, click
**Continue → Install**, type their Mac password, paste the enrollment token
into a dialog, and they're done. They never open Terminal.

```
packaging/macos/pkg/
├── build-pkg.sh              # run on your Mac → out/ComplianceGenie-Agent-<ver>.pkg
├── distribution.xml.in       # installer wizard definition (pages, macOS 12+, Intel + Apple silicon)
├── entitlements.plist        # hardened-runtime entitlements (needed for notarization)
├── scripts/
│   ├── preinstall            # stops a running agent (upgrades)
│   └── postinstall           # token dialog, writes config, starts LaunchDaemon, verifies enrollment
├── resources/
│   ├── welcome.html          # first wizard page
│   └── conclusion.html       # last wizard page
└── payload-extras/
    ├── uninstall.sh          # → /usr/local/compliancegenie/uninstall.sh
    └── uninstaller.applescript  # → /Applications/Uninstall ComplianceGenie Agent.app
```

Put this `pkg` folder at `Compliancegenie-Agent-MacOS/packaging/macos/pkg`.
The build script reads `dist/compliancegenie-agent`, `dist/config.json`, and
`packaging/macos/com.compliancegenie.agent.plist` from the agent tree as they are now.

---

## 1. What the client sees

1. Download `ComplianceGenie-Agent-x.y.z.pkg` from the portal and copy the token.
2. Double-click the .pkg → **Welcome** page → **Continue** → **Install** → enter Mac password.
3. A dialog asks for the token → paste → **Continue**.
4. The installer waits up to 60 s for the portal to accept the token:
   - **Accepted** → "ComplianceGenie Agent is installed" → **Close**.
   - **Rejected/expired** → dialog explains and asks again (3 tries max). If all fail or the user cancels, everything is rolled back.
   - **No internet** → agent stays installed and keeps retrying by itself.
5. To remove it: **Applications → Uninstall ComplianceGenie Agent** (asks for admin password).

This replaces your manual steps 2–10 and 13. `chmod`, `xattr` and `sudo` are no
longer needed, because files installed by Installer.app carry no quarantine flag.

## 2. Build it (on your Mac)

```bash
cd Compliancegenie-Agent-MacOS/packaging/macos/pkg
chmod +x build-pkg.sh
./build-pkg.sh 1.0.0                     # unsigned test build
open out/ComplianceGenie-Agent-1.0.0.pkg # try it
```

An unsigned build is fine for testing on your own Mac (right-click → Open, or
System Settings → Privacy & Security → **Open Anyway**). **Don't send unsigned
builds to clients.** On macOS 15+ the right-click bypass is gone, and
non-technical users won't get past the warning.

## 3. Sign and notarize (required for clients)

This is a one-time setup, done once per company:

1. Join the **Apple Developer Program** as an organisation (USD 99/yr; needs a D-U-N-S number for Cloudserve).
2. In Xcode → Settings → Accounts → Manage Certificates, create:
   - **Developer ID Application** (signs the agent binary + uninstaller app)
   - **Developer ID Installer** (signs the .pkg)
3. Create an app-specific password at appleid.apple.com, then store notary credentials:
   ```bash
   xcrun notarytool store-credentials cg-notary \
     --apple-id "you@cloudservesystems.com" --team-id TEAMID --password "app-specific-pw"
   ```

Every release after that:

```bash
export DEV_ID_APP="Developer ID Application: Cloudserve Systems Pvt. Ltd. (TEAMID)"
export DEV_ID_INSTALLER="Developer ID Installer: Cloudserve Systems Pvt. Ltd. (TEAMID)"
export NOTARY_PROFILE="cg-notary"
./build-pkg.sh 1.0.1
```

The script signs the agent with hardened runtime, signs the pkg, submits it for
notarization, staples the ticket, and runs a Gatekeeper check. The result opens
on any Mac with no warnings.

> **PyInstaller tip:** for the cleanest notarization, also sign during the
> PyInstaller build so the bundled Python dylibs get your Developer ID too:
> `pyinstaller --onefile --codesign-identity "$DEV_ID_APP" --osx-entitlements-file packaging/macos/pkg/entitlements.plist ...`

Run `security find-identity -v -p basic` to see the exact certificate names.

## 4. Silent install (MDM / IT admin)

```bash
echo "<ENROLLMENT_TOKEN>" | sudo tee /private/tmp/compliancegenie_enrollment_token >/dev/null
sudo installer -pkg ComplianceGenie-Agent-1.0.0.pkg -target /
```

The token can also go in `/Library/Application Support/ComplianceGenie/enrollment_token`
(easier to push from an MDM). The file is deleted after use. With a token file
present, no dialog is shown.

## 5. Upgrades

Run a newer .pkg over the old one. If the Mac is already enrolled (`device_id` and
`access_token` in `config.json`), the existing config is kept, no token is asked
for, and the agent restarts on the new binary. Machines installed with the old
manual steps upgrade the same way, because the paths are identical.

## 6. Where things go

| Path | What |
|---|---|
| `/usr/local/compliancegenie/compliancegenie-agent` | agent binary |
| `/usr/local/compliancegenie/config.json` | live config (0600, created at install) |
| `/usr/local/compliancegenie/config.template.json` | clean template shipped in the pkg |
| `/usr/local/compliancegenie/uninstall.sh` | uninstaller script |
| `/Library/LaunchDaemons/com.compliancegenie.agent.plist` | LaunchDaemon (unchanged from yours) |
| `/Applications/Uninstall ComplianceGenie Agent.app` | double-click uninstaller |
| `/var/log/compliancegenie-agent.{log,err}` | agent logs |
| `/var/log/install.log` | installer log; search for `[compliancegenie` |

At build time, `config.template.json` is cleaned of any `enrollment_token`,
`device_id`, `access_token`, `refresh_token` and `signing_secret` left over from
your local testing.

## 7. Admin commands (still useful)

```bash
sudo launchctl print system/com.compliancegenie.agent | head    # status
sudo launchctl bootout system/com.compliancegenie.agent         # stop until next boot / re-enable
sudo launchctl bootstrap system /Library/LaunchDaemons/com.compliancegenie.agent.plist
sudo /usr/local/compliancegenie/uninstall.sh                    # full removal
pkgutil --pkg-info com.cloudservesystems.compliancegenie.agent  # installed version
```

## 8. Full Disk Access

A .pkg can't grant Full Disk Access; macOS only lets the user or an MDM do that.
For clients with an MDM, push a PPPC profile that allows
`/usr/local/compliancegenie/compliancegenie-agent`. Without one, checks that
need FDA report what they can.
