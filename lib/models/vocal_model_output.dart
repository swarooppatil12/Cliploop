import 'segment.dart';

/// Raw output from the on-device vocal model run (steps 1–3 before structure mapping).
class VocalModelOutput {
  const VocalModelOutput({
    required this.vocalTimestamps,
    required this.nonVocalOppositeSegments,
    required this.nonVocalPartSegments,
    required this.rawLog,
  });

  /// Step 1 — where vocals are present on the model stem.
  final List<Segment> vocalTimestamps;

  /// Step 2 — opposite of vocals (instrumental / non-vocal spans).
  final List<Segment> nonVocalOppositeSegments;

  /// Step 3 — distinct non-vocal parts used to map Prelude / Interlude / Postlude.
  final List<Segment> nonVocalPartSegments;

  final String rawLog;

  factory VocalModelOutput.fromJson(Map<String, dynamic> json) {
    return VocalModelOutput(
      vocalTimestamps: (json['vocal_timestamps'] as List<dynamic>?)
              ?.map((item) => Segment.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      nonVocalOppositeSegments:
          (json['non_vocal_opposite_segments'] as List<dynamic>?)
                  ?.map((item) => Segment.fromJson(item as Map<String, dynamic>))
                  .toList() ??
              (json['non_vocal_segments'] as List<dynamic>?)
                  ?.map((item) => Segment.fromJson(item as Map<String, dynamic>))
                  .toList() ??
              const [],
      nonVocalPartSegments: (json['non_vocal_part_segments'] as List<dynamic>?)
              ?.map((item) => Segment.fromJson(item as Map<String, dynamic>))
              .toList() ??
          (json['non_vocal_segments'] as List<dynamic>?)
              ?.map((item) => Segment.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      rawLog: json['raw_log'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vocal_timestamps':
          vocalTimestamps.map((segment) => segment.toJson()).toList(),
      'non_vocal_opposite_segments':
          nonVocalOppositeSegments.map((segment) => segment.toJson()).toList(),
      'non_vocal_part_segments':
          nonVocalPartSegments.map((segment) => segment.toJson()).toList(),
      'raw_log': rawLog,
    };
  }
}
