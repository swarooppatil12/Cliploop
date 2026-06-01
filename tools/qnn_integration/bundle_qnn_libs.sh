#!/usr/bin/env bash
# Copy the QNN/QAIRT backend libs from an installed Qualcomm AI Engine Direct
# (QAIRT) SDK into the app's jniLibs so the ORT QNN EP can load the Hexagon NPU.
#
# Get the SDK (free Qualcomm account):
#   https://qpm.qualcomm.com/#/main/tools/details/Qualcomm_AI_Runtime_SDK
# Pick a QAIRT version compatible with ORT 1.24.x (see ORT release notes; the
# QNN EP must match the SDK it was built against). Installs to /opt/qairt/<ver>.
#
# Usage:  QAIRT=/opt/qairt/<ver> bash tools/qnn_integration/bundle_qnn_libs.sh
set -euo pipefail

QAIRT="${QAIRT:?set QAIRT to the SDK root, e.g. QAIRT=/opt/qairt/2.34.0}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$REPO/android/app/src/main/jniLibs/arm64-v8a"
A="$QAIRT/lib/aarch64-android"
[ -d "$A" ] || { echo "ERROR: $A not found — is QAIRT pointed at the SDK root?"; exit 1; }
mkdir -p "$DEST"

echo "Copying core HTP backend libs..."
for f in libQnnHtp.so libQnnSystem.so libQnnHtpPrepare.so; do
  cp -v "$A/$f" "$DEST/"
done

# Per-Hexagon-arch stub (host side, in aarch64-android) + skel (DSP side, in hexagon-vNN).
# v69=8Gen1  v73=8Gen2  v75=8Gen3  v79=8Elite  v81=8EliteGen5 (verify exact vNN).
echo "Copying per-arch HTP stubs + skels (supported range only; 7-series skipped)..."
for v in 69 73 75 79 81; do
  stub="$A/libQnnHtpV${v}Stub.so"
  skel="$QAIRT/lib/hexagon-v${v}/unsigned/libQnnHtpV${v}Skel.so"
  [ -f "$stub" ] && cp -v "$stub" "$DEST/" || echo "  (no v$v stub — skip)"
  [ -f "$skel" ] && cp -v "$skel" "$DEST/" || echo "  (no v$v skel — skip)"
done

echo; echo "Bundled into $DEST:"; ls -1 "$DEST"
echo
echo "Next: ensure native libs are extracted (HTP skels load from disk) —"
echo "      android.packaging.jniLibs.useLegacyPackaging=true is set in app gradle."
echo "Then: bash tools/qnn_integration/setup_qnn_fork.sh && flip uvrUseQnnOnAndroid=true && rebuild."
