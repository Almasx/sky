#!/bin/bash
# The Xcode Run button, headless: build, install, and relaunch Sky — then keep
# watching Swift sources and re-run on every save.
#
# Usage: scripts/dev.sh          run on the connected iPhone, rebuild on change
#        scripts/dev.sh --sim    run on the simulator instead
#        scripts/dev.sh --once   single build + launch (combinable with --sim)

set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.almas.sky"
USE_SIM=false
ONCE=false
for arg in "$@"; do
  case "$arg" in
    --sim) USE_SIM=true ;;
    --once) ONCE=true ;;
  esac
done

if $USE_SIM; then
  DEVICE_ID=$(xcrun simctl list devices | awk -F '[()]' '/Booted/ {print $2; exit}')
  if [[ -z "$DEVICE_ID" ]]; then
    DEVICE_ID=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone 17 Pro \(/ {print $2; exit}')
    echo "▸ booting simulator $DEVICE_ID"
    xcrun simctl boot "$DEVICE_ID"
  fi
  open -a Simulator
  PRODUCTS_DIR="Debug-iphonesimulator"
else
  DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | grep -m1 ' connected ' |
    grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
  if [[ -z "$DEVICE_ID" ]]; then
    echo "✗ no iPhone connected (check cable/wifi + unlocked)" >&2
    exit 1
  fi
  echo "▸ using device $DEVICE_ID"
  PRODUCTS_DIR="Debug-iphoneos"
fi

run() {
  echo "▸ $(date +%T) building…"
  local log
  if ! log=$(xcodebuild -project Sky.xcodeproj -scheme Sky \
      -destination "id=$DEVICE_ID" -allowProvisioningUpdates build 2>&1); then
    echo "$log" | grep -E "error:" | head -20
    echo "✗ build failed — waiting for next change"
    return 1
  fi
  local app
  app=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Sky-*/Build/Products/$PRODUCTS_DIR/Sky.app | head -1)
  if $USE_SIM; then
    xcrun simctl install "$DEVICE_ID" "$app"
    xcrun simctl launch --terminate-running-process "$DEVICE_ID" "$BUNDLE_ID" >/dev/null
  else
    xcrun devicectl device install app --device "$DEVICE_ID" "$app" >/dev/null
    xcrun devicectl device process launch --device "$DEVICE_ID" \
      --terminate-existing "$BUNDLE_ID" >/dev/null
  fi
  echo "✓ $(date +%T) running"
}

run
$ONCE && exit 0

snapshot() {
  find Sky -name '*.swift' -print0 2>/dev/null | sort -z | xargs -0 stat -f '%N %m' 2>/dev/null
}

last=$(snapshot)
echo "▸ watching Sky/**/*.swift — ctrl-C to stop"
while sleep 1; do
  now=$(snapshot)
  if [[ "$now" != "$last" ]]; then
    last=$now
    run
  fi
done
