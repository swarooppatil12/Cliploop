#!/usr/bin/env bash
# Reliable iOS device run when `flutter run` fails on Xcode CONFIGURATION_BUILD_DIR.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_ID="${1:-00008130-001851D821F2001C}"

echo "Building debug IPA for device..."
flutter build ios --debug

echo "Installing on $DEVICE_ID..."
flutter install -d "$DEVICE_ID"

echo "Attaching debugger (hot reload works after attach)..."
flutter attach -d "$DEVICE_ID"
