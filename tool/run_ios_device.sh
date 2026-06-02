#!/usr/bin/env bash
# Fast iOS device run: skips pub get, prefers USB over wireless, optional profile mode.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-debug}"
shift || true

extra_args=()
case "$MODE" in
  debug) ;;
  profile) extra_args+=(--profile) ;;
  release) extra_args+=(--release) ;;
  *)
    echo "Usage: $0 [debug|profile|release] [flutter run args...]"
    exit 1
    ;;
esac

pick_device() {
  flutter devices --machine 2>/dev/null | python3 -c "
import json, sys
try:
    devices = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)
ios = [
    d for d in devices
    if d.get('platformType') == 'ios' or 'ios' in str(d.get('targetPlatform', ''))
]
if not ios:
    sys.exit(1)
wired = [d for d in ios if 'wireless' not in d.get('name', '').lower()]
chosen = (wired or ios)[0]
if 'wireless' in chosen.get('name', '').lower():
    print('WARN:wireless', file=sys.stderr)
print(chosen['id'])
" 2>/dev/null || true
}

DEVICE="$(pick_device)"
if [[ -z "${DEVICE}" ]]; then
  echo "No iOS device found. Connect your iPhone with a USB cable, unlock it, and trust this Mac."
  flutter devices
  exit 1
fi

if flutter devices 2>/dev/null | grep -q "(wireless)"; then
  if ! flutter devices 2>/dev/null | grep -v "(wireless)" | grep -q "ios •"; then
    echo ""
    echo "Tip: Your iPhone is on wireless debugging only. Plug in USB for much faster install and attach."
    echo "     On the phone: Settings → Developer → connect via cable, or disable 'Connect via network'."
    echo ""
  fi
fi

echo "Running on device $DEVICE (${MODE} mode)..."
exec flutter run --no-pub -d "$DEVICE" "${extra_args[@]}" "$@"
