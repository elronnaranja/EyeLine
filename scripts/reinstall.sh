#!/bin/zsh
# Rebuild EyeLine with a fresh 7-day free signing profile and install it on the iPhone.
# Usage: ./scripts/reinstall.sh   (phone unlocked, on the cable or same Wi-Fi as the Mac)
set -euo pipefail
cd "${0:A:h}/.."
BUNDLE=com.theorange.eyeline
DD=/tmp/eyeline-build
STAMP=.last-install   # holds the current install's expiry (epoch seconds)
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
notify() { osascript -e "display notification \"$1\" with title \"EyeLine\"" 2>/dev/null || true; }

# --auto (for a daily Mac job): skip unless fewer than 2 days are left.
if [[ "${1:-}" == "--auto" && -f "$STAMP" ]]; then
  (( $(cat "$STAMP") - $(date +%s) > 172800 )) && { echo "$(date): not due yet"; exit 0; }
fi

# Remove only EyeLine's cached profile so Xcode issues a new 7-day one.
for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision(N); do
  if security cms -D -i "$f" 2>/dev/null | grep -q "\.${BUNDLE}<"; then rm -f "$f"; fi
done

xcodebuild -project EyeLine.xcodeproj -scheme EyeLine -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
  -allowProvisioningUpdates build -quiet

APP="$DD/Build/Products/Release-iphoneos/EyeLine.app"
DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /(connected|available)/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{4}-/) print $i}' | head -1)
[[ -z "$DEVICE" ]] && { echo "$(date): iPhone not found"; notify "Renew failed: iPhone not found. Unlock it near the Mac and run it again."; exit 1; }

xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null
EXP=$(security cms -D -i "$APP/embedded.mobileprovision" | plutil -extract ExpirationDate raw -o - -)
date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$EXP" +%s > "$STAMP"
echo "$(date): EyeLine installed. Works until $EXP (UTC)."
notify "Renewed. Works for 7 more days."
