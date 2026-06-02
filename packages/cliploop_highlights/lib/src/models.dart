/// Which compute backend produced the separation.
enum SeparationBackend {
  /// Qualcomm Hexagon NPU (Android, TFLite + QNN delegate).
  hexagonNpu,

  /// Apple Neural Engine via Core ML (iOS).
  coreml,

  /// CPU (XNNPACK / plain) — the cross-platform fallback.
  cpu,
}

/// A separated vocals + instrumental stem pair, written to disk as 16-bit WAV.
class SeparationStems {
  const SeparationStems({
    required this.vocalsPath,
    required this.instrumentalPath,
    required this.sampleRate,
    required this.durationSeconds,
    required this.backend,
    required this.wallMs,
  });

  final String vocalsPath;
  final String instrumentalPath;
  final int sampleRate;
  final double durationSeconds;

  /// Backend that actually ran the model (NPU vs fallback).
  final SeparationBackend backend;

  /// Wall-clock separation time in milliseconds.
  final int wallMs;

  @override
  String toString() =>
      'SeparationStems(backend: $backend, ${wallMs}ms, ${durationSeconds.toStringAsFixed(1)}s)';
}

/// A detected non-vocal highlight section of a song.
enum SongSectionType { prelude, interlude, postlude }

class SongSection {
  const SongSection({
    required this.type,
    required this.startSeconds,
    required this.endSeconds,
    required this.label,
  });

  final SongSectionType type;
  final double startSeconds;
  final double endSeconds;

  /// Human-facing label, e.g. "Interlude 1 · instrumental".
  final String label;

  double get durationSeconds => endSeconds - startSeconds;

  @override
  String toString() =>
      '$label [${startSeconds.toStringAsFixed(1)}–${endSeconds.toStringAsFixed(1)}s]';
}

/// Full highlight-analysis result: the stems plus the detected sections.
class HighlightResult {
  const HighlightResult({
    required this.stems,
    required this.sections,
    required this.durationSeconds,
  });

  final SeparationStems stems;
  final List<SongSection> sections;
  final double durationSeconds;

  Iterable<SongSection> get interludes =>
      sections.where((s) => s.type == SongSectionType.interlude);
  SongSection? get prelude => sections
      .where((s) => s.type == SongSectionType.prelude)
      .cast<SongSection?>()
      .firstWhere((_) => true, orElse: () => null);
  SongSection? get postlude => sections
      .where((s) => s.type == SongSectionType.postlude)
      .cast<SongSection?>()
      .firstWhere((_) => true, orElse: () => null);
}
