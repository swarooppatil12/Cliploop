#!/usr/bin/env bash
# Copy Qualcomm QNN runtime libs into the Android APK for Hexagon HTP / NPU.
#
# Prerequisite: download QNN SDK (v2.40.0.251030 recommended) from Qualcomm:
#   https://k2-fsa.github.io/sherpa/onnx/qnn/download-qnn.html
#
# Usage:
#   export QNN_SDK_ROOT=$HOME/qnn/qairt/2.40.0.251030
#   ./scripts/copy_qnn_android_libs.sh
#
# SM8850 (Galaxy S26 Ultra / Snapdragon 8 Elite Gen 5) needs V81 stub + skel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/android/app/src/main/jniLibs/arm64-v8a"

if [[ -z "${QNN_SDK_ROOT:-}" ]]; then
  echo "Set QNN_SDK_ROOT to your extracted QNN SDK directory." >&2
  exit 1
fi

if [[ ! -d "$QNN_SDK_ROOT/lib/aarch64-android" ]]; then
  echo "Missing $QNN_SDK_ROOT/lib/aarch64-android" >&2
  exit 1
fi

# Detect HTP arch from optional HTP_ARCH env or default V81 (SM8850+).
HTP_ARCH="${HTP_ARCH:-V81}"
HTP_HEX="$(echo "$HTP_ARCH" | tr '[:upper:]' '[:lower:]')"
HEX_DIR="$QNN_SDK_ROOT/lib/hexagon-$HTP_HEX/unsigned"

mkdir -p "$DEST"

ANDROID_LIB="$QNN_SDK_ROOT/lib/aarch64-android"
for lib in libQnnHtp.so libQnnHtpPrepare.so libQnnSystem.so "libQnnHtp${HTP_ARCH}Stub.so"; do
  src="$ANDROID_LIB/$lib"
  if [[ ! -f "$src" ]]; then
    echo "Missing $src — check HTP_ARCH (current: $HTP_ARCH)" >&2
    exit 1
  fi
  cp -v "$src" "$DEST/"
done

SKEL="libQnnHtp${HTP_ARCH}Skel.so"
if [[ -f "$HEX_DIR/$SKEL" ]]; then
  cp -v "$HEX_DIR/$SKEL" "$DEST/"
else
  echo "Missing $HEX_DIR/$SKEL — check HTP_ARCH" >&2
  exit 1
fi

echo "QNN libs copied to $DEST"
ls -lh "$DEST"/libQnn*.so
