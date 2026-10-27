#!/usr/bin/env bash
# Remove the ComplianceGenie agent LaunchDaemon. Run with sudo.
#   sudo ./packaging/macos/uninstall.sh
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Must run with sudo."; exit 1; fi
PLIST=/Library/LaunchDaemons/com.compliancegenie.agent.plist
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -rf /usr/local/compliancegenie
echo "Uninstalled."
