# Qualcomm GPU (Adreno) backend for UVR separation — validation & integration

iOS hits sub-60s vocal separation because the CoreML EP offloads UVR-MDX-Net to
the Apple Neural Engine. Android has no universal NPU API, so we target one
vendor: **Qualcomm**, via the ONNX Runtime **QNN Execution Provider, GPU
(Adreno) backend**. The GPU backend is chosen over the HTP/NPU backend because:

- It runs **float32/float16 models with no quantization** — UVR-MDX-Net stays
  exactly as-is (the HTP/NPU backend would require INT8 quantization + a
  calibration dataset, with real audio-quality risk).
- The Adreno GPU is more uniformly reachable across Snapdragon SoCs than HTP.

This only benefits **Snapdragon** users. Everyone else (MediaTek/Exynos/Tensor)
keeps falling back to XNNPACK (CPU), which is already wired up.

---

## Step 0 — measure the current CPU baseline (already done)

`UvrSeparationService` is instrumented (debug builds only). Run a separation on
a real Snapdragon device and read logcat:

```bash
flutter run --debug
adb logcat -s flutter | grep "UVR"
```

You get:

```
[UVR][timing] audio=…s wall=…s rtf=…x providers=… threads=…
[UVR][timing] sessionOpen=…ms | onnx=…ms (…%, N calls, …ms/call) | dsp=…ms (…%) | other=…ms
```

The `onnx %` is the ceiling: an infinitely fast GPU can only remove that slice.
The `ms/call` is the number to beat in Step 1. If `onnx %` is small (≲50%), the
GPU is the wrong lever — attack DSP/chunking instead and stop here.

---

## Step 1 — validate the Adreno win WITHOUT a device or custom build

`profile_uvr_qnn.py` profiles the exact ONNX on Qualcomm's cloud device farm.

```bash
pip install qai-hub
qai-hub configure --api_token <TOKEN>     # free signup: https://aihub.qualcomm.com
python profile_uvr_qnn.py --device "Snapdragon 8 Elite QRD"
```

It reports on-device inference latency for `cpu`, `gpu` (QNN/Adreno), and `htp`.

**Decision gate:** compare `gpu` latency against the `ms/call` from Step 0.
- GPU clearly faster → proceed to Step 2.
- GPU not faster (or heavy CPU fallback in the op breakdown) → stop; the model's
  ops aren't GPU-friendly and the integration won't pay off.

> The exact AI Hub flag for QNN GPU-vs-HTP backend selection is evolving (GPU
> backend is a 2025 preview). If a job rejects `--qnn_options backend_type=gpu`,
> check the current syntax at
> <https://app.aihub.qualcomm.com/docs/hub/profile_examples.html> and update
> `OPTIONS_GPU` in the script.

---

## Step 2 — integration (only if Step 1 is positive)

Three changes, in order. None of this is needed unless the GPU win is real.

### 2a. Fork `flutter_onnxruntime` and swap in a QNN-enabled AAR

The stock dep does **not** include the QNN EP:

```
flutter_onnxruntime/android/build.gradle
  implementation 'com.microsoft.onnxruntime:onnxruntime-android:1.22.0'   // CPU/XNNPACK/NNAPI only
```

Replace with a QNN-enabled ORT build — either the standalone `onnxruntime-qnn`
package (≥2.0.0) or a custom build (`--use_qnn --qnn_home <QNN_SDK>`), and
package the QNN runtime `.so`s **including `libQnnGpu.so`** into the APK's
`jniLibs/arm64-v8a`. (HTP-only builds won't have the GPU backend lib.)

### 2b. Make the QNN branch select the GPU backend

The plugin currently passes empty options
(`FlutterOnnxruntimePlugin.kt`):

```kotlin
"QNN" -> {
    ortSessionOptions.addQnn(mapOf())          // <-- no backend specified
}
```

Change to select the Adreno GPU backend:

```kotlin
"QNN" -> {
    ortSessionOptions.addQnn(mapOf("backend_type" to "gpu"))
    // or: mapOf("backend_path" to "libQnnGpu.so")
}
```

(For a cleaner long-term fix, thread a backend option through the Dart
`createSession` API instead of hardcoding — but hardcoding GPU is fine for a
first cut since we only ever want GPU here.)

### 2c. Add the Android provider branch in the app

`lib/services/uvr_separation_service.dart`, `_uvrProviders()` — today:

```dart
if (Platform.isAndroid && available.contains(OrtProvider.XNNPACK)) {
  return [OrtProvider.XNNPACK, OrtProvider.CPU];
}
```

Add QNN ahead of XNNPACK, gated by availability (so non-Snapdragon devices and
QNN-init failures fall back cleanly):

```dart
if (Platform.isAndroid && available.contains(OrtProvider.QNN)) {
  return [OrtProvider.QNN, OrtProvider.XNNPACK, OrtProvider.CPU];
}
if (Platform.isAndroid && available.contains(OrtProvider.XNNPACK)) {
  return [OrtProvider.XNNPACK, OrtProvider.CPU];
}
```

The existing `_openSession` try/catch already falls back to CPU if session
creation throws, so a QNN failure won't brick separation. Put this behind a
remote/feature flag for staged rollout. Re-run Step 0's `[UVR][timing]` on real
Snapdragon hardware to confirm the win holds end-to-end (not just per-op).

---

## Files

- `profile_uvr_qnn.py` — Step 1 AI Hub validation script.
- in-app instrumentation lives in
  `lib/services/uvr_separation_service.dart` (`[UVR][timing]` logs).
