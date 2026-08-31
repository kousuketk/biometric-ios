#!/bin/bash
# End-to-end check of the demo app without Appium.
#
# It drives the simulator with the same Darwin notifications that
# appium-ios-simulator posts for `mobile: enrollBiometric` and
# `mobile: sendBiometricMatch`, so a green run here means Appium will work too.
#
#   ./scripts/simctl-demo.sh [device-name-or-udid]

set -euo pipefail

DEVICE_QUERY="${1:-iPhone 17 Pro}"
BUNDLE_ID="com.magicpod.biometricdemo"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$PROJECT_DIR/build/Build/Products/Debug-iphonesimulator/BiometricDemo.app"

# Darwin notification names used by appium-ios-simulator.
ENROLL_NOTIFICATION="com.apple.BiometricKit.enrollmentChanged"
FACE_MATCH="com.apple.BiometricKit_Sim.pearl.match"
FACE_NOMATCH="com.apple.BiometricKit_Sim.pearl.nomatch"
TOUCH_MATCH="com.apple.BiometricKit_Sim.fingerTouch.match"
TOUCH_NOMATCH="com.apple.BiometricKit_Sim.fingerTouch.nomatch"

step() { printf '\n=== %s\n' "$1"; }

# Device names are not unique (several runtimes ship an "iPhone 17 Pro"), so
# resolve to a UDID once and keep using that. Prefer an already-booted match.
resolve_device() {
  local query="$1" listing line
  listing="$(xcrun simctl list devices available)"
  line="$(printf '%s\n' "$listing" | grep -F "$query" | grep -F '(Booted)' | tail -1 || true)"
  if [ -z "$line" ]; then
    line="$(printf '%s\n' "$listing" | grep -F "$query" | tail -1 || true)"
  fi
  if [ -z "$line" ]; then
    echo "No available simulator matches '$query'" >&2
    return 1
  fi
  printf '%s\n' "$line" | grep -oE '[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}' | head -1
}

step "Resolving '$DEVICE_QUERY'"
DEVICE="$(resolve_device "$DEVICE_QUERY")"
xcrun simctl list devices available | grep -F "$DEVICE"

step "Building"
xcodebuild -project "$PROJECT_DIR/BiometricDemo.xcodeproj" \
  -scheme BiometricDemo -sdk iphonesimulator -configuration Debug \
  -derivedDataPath "$PROJECT_DIR/build" \
  -destination 'generic/platform=iOS Simulator' build >/dev/null

step "Booting"
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

step "Installing"
xcrun simctl install "$DEVICE" "$APP"

step "Enrolling biometry (mobile: enrollBiometric equivalent)"
xcrun simctl spawn "$DEVICE" notifyutil -s "$ENROLL_NOTIFICATION" 1
xcrun simctl spawn "$DEVICE" notifyutil -p "$ENROLL_NOTIFICATION"

step "Launching with auto-auth and sending a match"
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" --gate-off --auto-auth BIOMETRICS_ONLY
# A cold-booted simulator can take several seconds to put the prompt up, and a
# match posted before then is simply dropped. Re-post a few times; an extra
# match after success is harmless.
for _ in 1 2 3 4 5; do
  sleep 3
  xcrun simctl spawn "$DEVICE" notifyutil -p "$FACE_MATCH" >/dev/null
done
sleep 2
xcrun simctl io "$DEVICE" screenshot "$PROJECT_DIR/build/result-success.png" >/dev/null

step "Done"
echo "Screenshot: $PROJECT_DIR/build/result-success.png"
echo "Expected: result_status = SUCCESS"
echo
echo "Other notifications you can post:"
echo "  Face ID  no-match : $FACE_NOMATCH"
echo "  Touch ID match    : $TOUCH_MATCH"
echo "  Touch ID no-match : $TOUCH_NOMATCH"
echo "  Un-enroll         : notifyutil -s $ENROLL_NOTIFICATION 0 && notifyutil -p $ENROLL_NOTIFICATION"
