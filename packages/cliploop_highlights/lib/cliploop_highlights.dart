/// On-device music source separation + song highlight detection.
///
/// ```dart
/// // Layer 1 — separation (vocals + instrumental stems)
/// final stems = await CliploopSeparator.separate('/path/song.mp3');
/// print('${stems.backend} in ${stems.wallMs}ms → ${stems.vocalsPath}');
///
/// // Layer 2 — highlights (prelude / interlude / postlude)
/// final h = await CliploopHighlights.analyze('/path/song.mp3');
/// for (final s in h.sections) print(s); // e.g. "Interlude 1 · instrumental [66.1–90.0s]"
/// ```
library;

import 'package:flutter/foundation.dart';

import 'src/models.dart';
import 'src/separation_engine.dart';

export 'src/models.dart';

/// Per-chunk callback for streaming separation. [vocChunk] / [instChunk] are mono
/// sample windows; [chunkStartSample] is the chunk's offset in the full track.
typedef StemChunkCallback = void Function(
  Float32List vocChunk,
  Float32List instChunk,
  int chunkStartSample,
);

/// Layer 1 — vocal/instrumental separation. Hexagon NPU on Android (TFLite+QNN),
/// Core ML on iOS, CPU fallback.
class CliploopSeparator {
  CliploopSeparator._();

  /// File mode: writes vocals + instrumental WAVs and returns their paths. Use
  /// when you need playback / export / inspection.
  static Future<SeparationStems> separate(
    String audioPath, {
    void Function(double progress)? onProgress,
  }) =>
      SeparationEngine.instance.separate(audioPath, onProgress: onProgress);

  /// Streaming mode: delivers stems chunk-by-chunk via [onChunk] with **no disk
  /// I/O** (no temp WAVs, no peak-normalization pass). Use when you only need
  /// analysis-time access to the samples (e.g. RMS envelopes for section
  /// detection). The callback fires on the calling isolate.
  static Future<SeparationStreamResult> separateStreaming(
    String audioPath, {
    required StemChunkCallback onChunk,
    void Function(double progress)? onProgress,
  }) =>
      SeparationEngine.instance.separateStreaming(
        audioPath,
        onChunk: onChunk,
        onProgress: onProgress,
      );
}

/// Layer 2 — highlight detection (prelude / interlude / postlude), built on
/// separation. Section detection runs on the clean separated vocals (energy +
/// position logic; no neural VAD).
class CliploopHighlights {
  CliploopHighlights._();

  static Future<HighlightResult> analyze(
    String audioPath, {
    void Function(double progress)? onProgress,
  }) async {
    // Stage A: separation is wired. Stage B (structure/section extraction from the
    // app engine) is in progress — until then sections is empty.
    final stems =
        await SeparationEngine.instance.separate(audioPath, onProgress: onProgress);
    if (kDebugMode) {
      debugPrint(
        '[cliploop_highlights] section detection not yet ported (Stage B); '
        'returning stems with empty sections.',
      );
    }
    return HighlightResult(
      stems: stems,
      sections: const [],
      durationSeconds: stems.durationSeconds,
    );
  }
}
