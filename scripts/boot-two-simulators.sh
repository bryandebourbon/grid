#!/bin/zsh
# Boot two iOS Simulators, install Grid on both, and drop them next to each
# other on the map. Each simulator gets its own device ID (UDID / -GridPeerName)
# so they can share one Apple ID and still see each other.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ALICE_NAME="${ALICE_NAME:-iPhone 17}"
BOB_NAME="${BOB_NAME:-iPhone 17 Pro}"
OS="${SIM_OS:-26.5}"
BUNDLE_ID="com.bryandebourbon.grid"
DERIVED="${DERIVED:-/tmp/grid-two-sim-dd}"

pick_udid() {
  local name="$1"
  python3 - "$name" "$OS" <<'PY'
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

ALICE_UDID="$(pick_udid "$ALICE_NAME")"
BOB_UDID="$(pick_udid "$BOB_NAME")"

echo "Alice: $ALICE_NAME ($ALICE_UDID)"
echo "Bob:   $BOB_NAME ($BOB_UDID)"

echo "Building…"
xcodebuild -scheme grid \
  -destination "platform=iOS Simulator,id=$ALICE_UDID" \
  -derivedDataPath "$DERIVED" \
  -quiet \
  build

APP="$DERIVED/Build/Products/Debug-iphonesimulator/grid.app"
if [[ ! -d "$APP" ]]; then
  echo "Build did not produce $APP" >&2
  exit 1
fi

open -a Simulator
xcrun simctl boot "$ALICE_UDID" >/dev/null 2>&1 || true
xcrun simctl boot "$BOB_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$ALICE_UDID" -b
xcrun simctl bootstatus "$BOB_UDID" -b

xcrun simctl install "$ALICE_UDID" "$APP"
xcrun simctl install "$BOB_UDID" "$APP"

# A few meters apart in SF so proximity treats them as nearby.
xcrun simctl location "$ALICE_UDID" set 37.77490,-122.41940
xcrun simctl location "$BOB_UDID" set 37.77495,-122.41935

xcrun simctl terminate "$ALICE_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl terminate "$BOB_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

xcrun simctl launch "$ALICE_UDID" "$BUNDLE_ID" -GridPeerName Alice
xcrun simctl launch "$BOB_UDID" "$BUNDLE_ID" -GridPeerName Bob

cat <<EOF

Both simulators are running Grid.

1. Sign in with Apple on each (same Apple ID is fine).
2. Create / open a profile on each — they should appear on each other's grid.
3. Send a message from Alice and confirm Bob's banner shows the text.

To inject a fake push later (after a real CloudKit record exists):
  xcrun simctl push $BOB_UDID $BUNDLE_ID /path/to/payload.apns

EOF
