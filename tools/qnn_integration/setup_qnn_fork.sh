#!/usr/bin/env bash
# Vendors flutter_onnxruntime into third_party/ and patches the QNN branch to
# select the Hexagon HTP backend, then wires a path override in pubspec.yaml.
#
# Why a fork: the QNN provider needs `backend_path=libQnnHtp.so`, but the plugin
# (1.7.1) calls addQnn(mapOf()) with no options and exposes no Dart hook for it.
# This is the ONLY plugin change required.
#
# Run from repo root:  bash tools/qnn_integration/setup_qnn_fork.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$REPO/third_party/flutter_onnxruntime"
SRC="$(find "$HOME/.pub-cache/hosted/pub.dev" -maxdepth 1 -type d -name 'flutter_onnxruntime-*' | sort -V | tail -1)"

[ -n "$SRC" ] || { echo "ERROR: flutter_onnxruntime not in pub-cache. Run 'flutter pub get' first."; exit 1; }
echo "Vendoring $SRC -> $DEST"
rm -rf "$DEST"; mkdir -p "$(dirname "$DEST")"; cp -R "$SRC" "$DEST"

KT="$DEST/android/src/main/kotlin/com/masicai/flutteronnxruntime/FlutterOnnxruntimePlugin.kt"
echo "Patching QNN backend in $(basename "$KT")"
# addQnn(mapOf())  ->  addQnn(mapOf("backend_path" to "libQnnHtp.so"))
perl -0pi -e 's/addQnn\(mapOf\(\)\)/addQnn(mapOf("backend_path" to "libQnnHtp.so"))/g' "$KT"
grep -q 'backend_path' "$KT" && echo "  ✓ patched" || { echo "  ✗ patch failed — inspect $KT"; exit 1; }

echo "Wiring pubspec dependency_overrides"
python3 - "$REPO/pubspec.yaml" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
if 'third_party/flutter_onnxruntime' in s:
    print("  (override already present)"); sys.exit(0)
ovr = "  flutter_onnxruntime:\n    path: third_party/flutter_onnxruntime\n"
if re.search(r'(?m)^dependency_overrides:\s*$', s):
    s = re.sub(r'(?m)^(dependency_overrides:\s*\n)', r'\1' + ovr, s, count=1)
else:
    s += "\ndependency_overrides:\n" + ovr
open(p, 'w').write(s); print("  ✓ added path override")
PY

echo "Running flutter pub get"
( cd "$REPO" && flutter pub get >/dev/null && echo "  ✓ resolved" )
echo
echo "DONE. Next: bundle QAIRT backend libs (see docs/android-npu-integration.md),"
echo "then set ProcessingConstants.uvrUseQnnOnAndroid = true and rebuild."
