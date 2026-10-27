#!/bin/bash
# Build the double-click macOS installer (.pkg) for the ComplianceGenie agent.
# Run on a Mac (needs pkgbuild/productbuild, which ship with macOS).
#
#   ./build-pkg.sh [VERSION]                 # unsigned, for internal testing
#
#   # Signed + notarized, ready to give to clients:
#   export DEV_ID_APP="Developer ID Application: Cloudserve Systems Pvt. Ltd. (TEAMID)"
#   export DEV_ID_INSTALLER="Developer ID Installer: Cloudserve Systems Pvt. Ltd. (TEAMID)"
#   export NOTARY_PROFILE="cg-notary"        # see README: notarytool store-credentials
#   ./build-pkg.sh 1.2.0
#
# Optional:  SERVER_URL  (default https://portal.compliancegenie.cloudservesystems.com)
#
# Output: packaging/macos/pkg/out/ComplianceGenie-Agent-<VERSION>.pkg
set -euo pipefail

VERSION="${1:-1.0.0}"
PKG_ID="com.cloudservesystems.compliancegenie.agent"
SERVER_URL="${SERVER_URL:-https://portal.compliancegenie.cloudservesystems.com}"
DEV_ID_APP="${DEV_ID_APP:-}"
DEV_ID_INSTALLER="${DEV_ID_INSTALLER:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

HERE="$(cd "$(dirname "$0")" && pwd)"
AGENT_ROOT="$(cd "$HERE/../../.." && pwd)"            # .../Compliancegenie-Agent-MacOS
BIN_SRC="$AGENT_ROOT/dist/compliancegenie-agent"
CFG_SRC="$AGENT_ROOT/dist/config.json"
PLIST_SRC="$AGENT_ROOT/packaging/macos/com.compliancegenie.agent.plist"

BUILD="$HERE/build"
ROOT="$BUILD/root"
OUT="$HERE/out"
FINAL="$OUT/ComplianceGenie-Agent-${VERSION}.pkg"
UNINSTALLER_APP_NAME="Uninstall ComplianceGenie Agent.app"

step() { printf '\n==> %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Run this on macOS."
for f in "$BIN_SRC" "$CFG_SRC" "$PLIST_SRC"; do [[ -f "$f" ]] || die "missing $f"; done
plutil -lint "$PLIST_SRC" >/dev/null || die "LaunchDaemon plist is invalid"
echo "Agent architectures: $(lipo -archs "$BIN_SRC")"

# ------------------------------------------------------------------ stage
step "Staging payload"
rm -rf "$BUILD"; mkdir -p "$ROOT/usr/local/compliancegenie" "$ROOT/Library/LaunchDaemons" \
                          "$ROOT/Applications" "$BUILD/scripts" "$OUT"
chmod 0755 "$ROOT/usr" "$ROOT/usr/local" "$ROOT/Library" "$ROOT/Library/LaunchDaemons" "$ROOT/Applications"

install -m 0755 "$BIN_SRC" "$ROOT/usr/local/compliancegenie/compliancegenie-agent"
install -m 0644 "$PLIST_SRC" "$ROOT/Library/LaunchDaemons/com.compliancegenie.agent.plist"
install -m 0755 "$HERE/payload-extras/uninstall.sh" "$ROOT/usr/local/compliancegenie/uninstall.sh"

# Config template: wipe anything left over from local testing (tokens, device
# identity) so one client never inherits another machine's credentials.
TEMPLATE="$ROOT/usr/local/compliancegenie/config.template.json"
cat > "$BUILD/sanitize.js" <<'JS'
ObjC.import('Foundation');
function run(argv) {
  var s = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  var cfg = JSON.parse(s.js);
  ['enrollment_token','device_id','access_token','refresh_token','signing_secret']
    .forEach(function (k) { cfg[k] = ''; });
  cfg.server_url = argv[2];
  $(JSON.stringify(cfg, null, 2) + '\n').writeToFileAtomicallyEncodingError(argv[1], true, $.NSUTF8StringEncoding, null);
  return 'ok';
}
JS
osascript -l JavaScript "$BUILD/sanitize.js" "$CFG_SRC" "$TEMPLATE" "$SERVER_URL" >/dev/null
chmod 0644 "$TEMPLATE"
echo "config template server_url = $SERVER_URL"

# Uninstaller app (double-click, asks for admin password, removes everything).
osacompile -o "$ROOT/Applications/$UNINSTALLER_APP_NAME" "$HERE/payload-extras/uninstaller.applescript"

# Strip quarantine / Finder metadata picked up while downloading or unzipping.
xattr -cr "$ROOT"

# ------------------------------------------------------------------ sign code
if [[ -n "$DEV_ID_APP" ]]; then
  step "Signing agent and uninstaller with: $DEV_ID_APP"
  codesign --force --timestamp --options runtime \
           --entitlements "$HERE/entitlements.plist" \
           --sign "$DEV_ID_APP" "$ROOT/usr/local/compliancegenie/compliancegenie-agent"
  codesign --force --timestamp --options runtime \
           --sign "$DEV_ID_APP" "$ROOT/Applications/$UNINSTALLER_APP_NAME"
  codesign --verify --strict --verbose=2 "$ROOT/usr/local/compliancegenie/compliancegenie-agent"
  codesign --verify --strict --verbose=2 "$ROOT/Applications/$UNINSTALLER_APP_NAME"
else
  echo "NOTE: DEV_ID_APP not set — binaries keep their existing (ad-hoc) signature."
fi

# ------------------------------------------------------------------ scripts
install -m 0755 "$HERE/scripts/preinstall"  "$BUILD/scripts/preinstall"
install -m 0755 "$HERE/scripts/postinstall" "$BUILD/scripts/postinstall"

# ------------------------------------------------------------------ component pkg
step "Building component package"
COMPONENTS="$BUILD/components.plist"
pkgbuild --analyze --root "$ROOT" "$COMPONENTS" >/dev/null
# Never let Installer "relocate" the uninstaller app to some other copy on disk.
i=0
while plutil -extract "$i" xml1 -o /dev/null "$COMPONENTS" 2>/dev/null; do
  plutil -replace "$i.BundleIsRelocatable" -bool NO "$COMPONENTS"
  i=$((i + 1))
done

pkgbuild --root "$ROOT" \
         --component-plist "$COMPONENTS" \
         --scripts "$BUILD/scripts" \
         --identifier "$PKG_ID" \
         --version "$VERSION" \
         --install-location / \
         --ownership recommended \
         "$BUILD/agent-component.pkg"

# ------------------------------------------------------------------ product pkg
step "Building installer"
sed -e "s/@VERSION@/$VERSION/g" -e "s/@PKG_ID@/$PKG_ID/g" \
    "$HERE/distribution.xml.in" > "$BUILD/distribution.xml"

SIGN_ARGS=()
[[ -n "$DEV_ID_INSTALLER" ]] && SIGN_ARGS=(--sign "$DEV_ID_INSTALLER" --timestamp)

rm -f "$FINAL"
productbuild --distribution "$BUILD/distribution.xml" \
             --resources "$HERE/resources" \
             --package-path "$BUILD" \
             "${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"}" \
             "$FINAL"

# ------------------------------------------------------------------ notarize
if [[ -n "$DEV_ID_INSTALLER" && -n "$NOTARY_PROFILE" ]]; then
  step "Notarizing (usually 1–5 minutes)"
  xcrun notarytool submit "$FINAL" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$FINAL"
  step "Gatekeeper check"
  spctl --assess --type install --verbose=2 "$FINAL"
elif [[ -n "$DEV_ID_INSTALLER" ]]; then
  echo "NOTE: signed but NOT notarized (set NOTARY_PROFILE). Clients will still see a Gatekeeper warning."
else
  echo
  echo "WARNING: unsigned build. Fine for testing on your own Mac, but clients will be"
  echo "blocked by Gatekeeper. Sign + notarize before distributing (see README.md)."
fi

pkgutil --check-signature "$FINAL" || true
step "Done: $FINAL"
