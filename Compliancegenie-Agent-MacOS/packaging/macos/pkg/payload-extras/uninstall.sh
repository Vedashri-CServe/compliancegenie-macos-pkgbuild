#!/bin/bash
# Removes the ComplianceGenie agent completely.
# Installed to /usr/local/compliancegenie/uninstall.sh and called by
# "Uninstall ComplianceGenie Agent.app". Admins can also run:
#   sudo /usr/local/compliancegenie/uninstall.sh
set -u
if [[ $EUID -ne 0 ]]; then echo "Must run with sudo."; exit 1; fi

LABEL="com.compliancegenie.agent"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
PKG_ID="com.cloudservesystems.compliancegenie.agent"

/bin/launchctl bootout "system/${LABEL}" 2>/dev/null \
  || /bin/launchctl unload "$PLIST" 2>/dev/null || true

rm -f "$PLIST" "${PLIST}.disabled"
rm -f /var/log/compliancegenie-agent.log /var/log/compliancegenie-agent.err
rm -rf "/Applications/Uninstall ComplianceGenie Agent.app"
/usr/sbin/pkgutil --forget "$PKG_ID" >/dev/null 2>&1 || true
rm -rf /usr/local/compliancegenie   # last: this script lives here

echo "ComplianceGenie Agent uninstalled."
