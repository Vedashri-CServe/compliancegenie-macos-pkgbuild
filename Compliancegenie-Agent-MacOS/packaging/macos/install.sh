#!/usr/bin/env bash
# Install the ComplianceGenie agent as a macOS LaunchDaemon.
# Run with sudo ON the target macOS 12+ machine, AFTER build.sh.
#
#   sudo ./packaging/macos/install.sh <ENROLLMENT_TOKEN> <SERVER_URL>
#
set -euo pipefail
TOKEN="${1:-}"; SERVER_URL="${2:-}"
if [[ -z "$TOKEN" || -z "$SERVER_URL" ]]; then
  echo "Usage: sudo $0 <ENROLLMENT_TOKEN> <SERVER_URL>"; exit 1
fi
if [[ $EUID -ne 0 ]]; then echo "Must run with sudo."; exit 1; fi

cd "$(dirname "$0")/../.."
INSTALL_DIR=/usr/local/compliancegenie
mkdir -p "$INSTALL_DIR"
install -m 0755 dist/compliancegenie-agent "$INSTALL_DIR/compliancegenie-agent"

# Binaries downloaded from the internet (e.g. a GitHub release asset) carry a
# Gatekeeper quarantine flag that blocks launch. Strip it now that the file is
# being installed by an admin onto a machine we manage.
xattr -dr com.apple.quarantine "$INSTALL_DIR/compliancegenie-agent" 2>/dev/null || true

# Confirm the code signature is intact (ad-hoc signature applied at build time).
codesign --verify --verbose "$INSTALL_DIR/compliancegenie-agent" 2>/dev/null \
  || echo "WARNING: code signature could not be verified; continuing."

# Write config with server URL + token.
python3 - "$SERVER_URL" "$TOKEN" > "$INSTALL_DIR/config.json" <<'PY'
import json, sys
cfg = json.load(open("config.json"))
cfg["server_url"] = sys.argv[1]
cfg["enrollment_token"] = sys.argv[2]
print(json.dumps(cfg, indent=2))
PY
chmod 0600 "$INSTALL_DIR/config.json"

# Install and load the LaunchDaemon.
PLIST=/Library/LaunchDaemons/com.compliancegenie.agent.plist
install -m 0644 packaging/macos/com.compliancegenie.agent.plist "$PLIST"
chown root:wheel "$PLIST"

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "Installed and loaded com.compliancegenie.agent."
echo "Check with:  sudo launchctl list | grep compliancegenie"
echo "Logs:        /var/log/compliancegenie-agent.log"
echo
echo "NOTE: on macOS, some posture checks (FileVault, firewall) work best when"
echo "the agent binary is granted Full Disk Access under System Settings >"
echo "Privacy & Security, or deployed via an MDM profile that pre-authorizes it."
