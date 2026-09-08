#!/bin/zsh
# One Simulator + your physical iPhone, same CloudKit Production container.
# The sim gets its own device ID, so it can share your Apple ID and still
# show up as a second person on the phone's grid.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SIM_NAME="${SIM_NAME:-iPhone 17}"
OS="${SIM_OS:-26.5}"
BUNDLE_ID="com.bryandebourbon.grid"
DERIVED="${DERIVED:-/tmp/grid-sim-peer-dd}"
# Default: downtown SF. Override with LAT=… LON=… to match your phone.
LAT="${LAT:-37.77490}"
LON="${LON:--122.41940}"

pick_udid() {
  python3 - "$SIM_NAME" "$OS" <<'PY'
import json, sys, subprocess
name, os_prefix = sys.argv[1], sys.argv[2]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
for runtime, devices in data.get("devices", {}).items():
    if os_prefix.replace(".", "-") not in runtime and os_prefix not in runtime:
        continue
    for device in devices:
        if device.get("name") == name and device.get("isAvailable", True):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit(f"No available simulator named {name!r} for OS {os_prefix}")
PY
}

UDID="$(pick_udid)"
echo "Simulator: $SIM_NAME ($UDID)"

echo "Building…"
xcodebuild -scheme grid \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED" \
  -quiet \
  build

APP="$DERIVED/Build/Products/Debug-iphonesimulator/grid.app"

open -a Simulator
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl location "$UDID" set "$LAT,$LON"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -GridPeerName Sim

cat <<EOF

Simulator is Grid as peer "Sim" at $LAT,$LON.

On the Simulator first:
  Settings → Sign in to iCloud (required for CloudKit)
  Then Sign in with Apple inside Grid (same Apple ID as the phone is fine)

On the iPhone:
  Run the same Grid scheme from Xcode (or the TestFlight build — both use Production)
  Pull to refresh the grid until you see the sim
  Send a message either way

Match the sim to your phone's map pin:
  LAT=37.78 LON=-122.41 ./scripts/boot-sim-peer.sh

EOF
