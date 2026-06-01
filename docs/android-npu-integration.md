# Android Hexagon NPU acceleration — integration guide

Run UVR-MDX-Net on the Snapdragon **Hexagon NPU** via the ONNX Runtime **QNN
Execution Provider**, to match/beat iOS (which uses CoreML→ANE).

**Validated on AI Hub (sm8850 = S26 Ultra's SoC):**
- NPU: **~42 ms/call vs 1849 ms CPU → ~44× faster** (whole model on NPU, 248 layers)
- Accuracy: **42.7 dB SDR vs FP32** — lossless-grade; section markers won't move
- Adreno GPU: total CPU fallback → **not** a path
- Projected: ~120 s → **~30–45 s per song, beats iOS**

**Scope (measured on AI Hub):** NPU acceleration is a **premium-tier** feature, not
age-based. Full on-NPU execution + big speedups on **8 Gen 1 → 8 Elite Gen 5**
(S22 14.5× … S26 44×). **Total CPU fallback (no speedup)** on Snapdragon 888 &
older AND **all 7-series mid-range, including the 2025 7 Gen 4**. So: target
**8 Gen 2+** (covers "last 3 years"; 8 Gen 1 is a bonus). Everyone else degrades
gracefully to XNNPACK/CPU — no regression, no win.

---

## Already applied in-repo (safe; no behavior change until enabled)
1. **`android/build.gradle.kts`** — substitutes `onnxruntime-android` → **`onnxruntime-android-qnn:1.24.3`** (adds the QNN EP; same VERS_1.24.3 symbols as sherpa, so no link conflict).
2. **`ProcessingConstants.uvrUseQnnOnAndroid`** — feature flag, **default `false`**.
3. **`UvrSeparationService._uvrProviders`** — flag-gated `QNN → XNNPACK → CPU` preference.
4. **`UvrSeparationService._openSession`** — graceful fallback ladder (QNN fail → XNNPACK → CPU), so a missing/!working NPU never breaks separation.

With the flag off, the app behaves exactly as today (XNNPACK/CPU).

## Step A — fork the plugin (one Kotlin line)
The QNN EP needs `backend_path=libQnnHtp.so`; the plugin calls `addQnn(mapOf())` with no options. Vendor + patch + wire the override:
```bash
bash tools/qnn_integration/setup_qnn_fork.sh
```
This copies `flutter_onnxruntime` into `third_party/`, patches `addQnn(...)`, adds a `dependency_overrides` path entry, and runs `flutter pub get`.

## Step B — bundle the QAIRT backend libs (the main task)
The `onnxruntime-android-qnn` AAR contains **only** `libonnxruntime*.so` — **not** the
QNN backend. Get these from the **Qualcomm AI Engine Direct (QAIRT) SDK**
(developer.qualcomm.com, free) and copy into `android/app/src/main/jniLibs/arm64-v8a/`:

| Lib | From QAIRT path | Purpose |
|-----|-----------------|---------|
| `libQnnHtp.so` | `lib/aarch64-android/` | HTP backend entry |
| `libQnnSystem.so` | `lib/aarch64-android/` | QNN system |
| `libQnnHtpPrepare.so` | `lib/aarch64-android/` | on-device graph prepare |
| `libQnnHtpV69Skel.so` | `lib/hexagon-v69/unsigned/` | **8 Gen 1** DSP skel (bonus, pre-cutoff) |
| `libQnnHtpV73Skel.so` | `lib/hexagon-v73/unsigned/` | **8 Gen 2** DSP skel |
| `libQnnHtpV75Skel.so` | `lib/hexagon-v75/unsigned/` | **8 Gen 3** DSP skel |
| `libQnnHtpV79Skel.so` | `lib/hexagon-v79/unsigned/` | **8 Elite** DSP skel |
| `libQnnHtpV*Skel.so`   | `lib/hexagon-v8x/unsigned/` | **8 Elite Gen 5** (verify version) |

Bundle one skel per Hexagon version in your support range (verify exact vNN per
chipset in the QAIRT release notes). **Don't bundle 7-series skels** — the 7 Gen 4
fell fully back to CPU in testing, so they add size for no benefit. Adds ~20–40 MB
to the APK; gate by ABI (arm64-v8a only). Keep `isMinifyEnabled = false` (already
set) so the libs aren't stripped. On unsupported devices the provider ladder
degrades to XNNPACK/CPU, so no device allowlist is strictly required.

## Step C — kill the ~31 s first-load (context cache)
First NPU run compiles the graph on-device (~31 s); warm runs are ~0.25 s. Enable
ORT QNN **context binary caching** so it compiles once and reuses:
- session options `ep.context_enable=1`, `ep.context_file_path=<app-cache>/uvr_qnn.bin`
- (also needs plugin support to pass these QNN options — extend the same `addQnn` map).
Ship a precompiled `.bin` per Hexagon version, or compile-on-first-run and cache.

## Step D — enable + validate on device
1. Set `ProcessingConstants.uvrUseQnnOnAndroid = true`.
2. `flutter run -d <device> --debug` on a real Snapdragon ≥8 Gen 2.
3. Confirm in logcat: `[UVR] segmented MDXNET ... providers=QNN, ...` and that
   `[UVR][timing]` onnx time collapses (~92 s → low single digits).
4. **Acceptance test:** the prelude/interlude/postlude markers match the FP32
   baseline (identification is the metric, not audio SNR). Use the accuracy
   harness; ±0.5 s on boundaries is fine.
5. Measure real wall time — target sub-60 s.

## Rollback
Flip `uvrUseQnnOnAndroid = false` (instant), or remove the `dependencySubstitution`
block to revert to the plain ORT build. The fallback ladder means even a broken QNN
setup degrades to XNNPACK/CPU rather than failing.
