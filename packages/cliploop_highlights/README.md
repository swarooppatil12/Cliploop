# cliploop_highlights

On-device music **source separation** (UVR MDX-Net) and song **highlight detection**
(prelude / interlude / postlude) — UI-free, drop-in.

- **Android:** Hexagon **NPU** via TFLite + Qualcomm QNN delegate (~17 s for a 4-min
  song on a Snapdragon 8 Elite; ~7× faster than CPU). Automatic CPU fallback.
- **iOS:** Core ML via `flutter_onnxruntime`.

## Status
| Layer | API | State |
|-------|-----|-------|
| 1 — Separation (file) | `CliploopSeparator.separate()` | ✅ ready |
| 1 — Separation (streaming) | `CliploopSeparator.separateStreaming()` | ✅ ready |
| 2 — Highlights | `CliploopHighlights.analyze()` | 🚧 separation wired; section detection porting (returns empty `sections` for now) |

## Install
```yaml
dependencies:
  cliploop_highlights:
    path: packages/cliploop_highlights   # or git/pub.dev once published
```

## Android setup (required)
The QNN HTP skel libs load from disk on the DSP, so the **consumer app** must extract
native libs. In `android/app/build.gradle.kts`:
```kotlin
android {
  packaging { jniLibs { useLegacyPackaging = true } }
}
```
Everything else is automatic: the `<uses-native-library libcdsprpc.so>` entry and the
`qnn-runtime` Hexagon libs (incl. v81) merge in from the plugin, and the `.tflite` model
is bundled. `minSdk 24+`. NPU engages on **Snapdragon 8 Gen 2+** (others fall back to CPU).

## Usage
```dart
import 'package:cliploop_highlights/cliploop_highlights.dart';

// Layer 1 — stems
final stems = await CliploopSeparator.separate(
  '/path/song.mp3',
  onProgress: (p) => print('${(p * 100).round()}%'),
);
print('${stems.backend} in ${stems.wallMs}ms');     // e.g. hexagonNpu in 17200ms
print(stems.vocalsPath);
print(stems.instrumentalPath);

// Layer 1 — streaming stems (no files; samples delivered per chunk)
final result = await CliploopSeparator.separateStreaming(
  '/path/song.mp3',
  onChunk: (vocChunk, instChunk, startSample) {
    // mono Float32 windows; e.g. accumulate RMS envelopes for section detection
  },
  onProgress: (p) => print('${(p * 100).round()}%'),
);
print('${result.backend} in ${result.wallMs}ms');

// Layer 2 — highlights
final h = await CliploopHighlights.analyze('/path/song.mp3');
for (final s in h.sections) {
  print(s);  // "Interlude 1 · instrumental [66.1–90.0s]"
}
```

### File mode vs streaming mode
- **`separate()` (file)** — writes vocals + instrumental WAVs to disk and returns
  their paths, with peak normalization. Use when you need **playback, export, or
  inspection** of the stems.
- **`separateStreaming()` (streaming)** — delivers mono stem samples chunk-by-chunk
  via `onChunk` with **no disk I/O** (no temp WAVs, no normalization pass). Use when
  you only need **analysis-time access** to the samples (e.g. computing RMS
  envelopes for your own section/highlight logic). Avoids the ~180 MB disk
  round-trip that otherwise contends for DRAM bandwidth during inference.

## How it works
1. Decode input → 16-bit stereo WAV (ffmpeg).
2. STFT → MDX-Net (Hexagon NPU / Core ML / CPU) → ISTFT → vocals + instrumental WAVs.
3. (Layer 2) Energy + position logic on the clean vocals stem → prelude/interlude/postlude.

**Runs off the main thread.** The heavy work (STFT/ISTFT + NPU inference + WAV writes)
runs in a spawned isolate via `BackgroundIsolateBinaryMessenger`, so `separate()` /
`analyze()` don't jank the host UI — `await` like any async call, use `onProgress` for a
progress bar. The ffmpeg decode runs on the main isolate (ffmpeg_kit isn't
background-isolate safe). Falls back to fully inline when there's no root isolate.

No neural VAD, no waveform extraction — both removed as unnecessary for highlight detection.

## License
Proprietary — Cliploop.
