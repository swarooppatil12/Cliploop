import 'segment.dart';
import 'track_stem.dart';
import 'vocal_model_output.dart';

class SeparationResult {
  final String musicFileId;
  final List<TrackStem> stems;
  final List<Segment> stemTimestamps;
  final List<Segment> structureSegments;
  final VocalModelOutput? vocalModelOutput;
  final DateTime processedAt;
  final String model;

  const SeparationResult({
    required this.musicFileId,
    required this.stems,
    required this.stemTimestamps,
    required this.structureSegments,
    this.vocalModelOutput,
    required this.processedAt,
    required this.model,
  });

  factory SeparationResult.fromJson(Map<String, dynamic> json) {
    return SeparationResult(
      musicFileId: json['music_file_id'] as String? ?? '',
      stems: (json['stems'] as List<dynamic>?)
              ?.map((item) => TrackStem.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      stemTimestamps: (json['stem_timestamps'] as List<dynamic>?)
              ?.map((item) => Segment.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      structureSegments: (json['structure_segments'] as List<dynamic>?)
              ?.map((item) => Segment.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      vocalModelOutput: json['vocal_model_output'] != null
          ? VocalModelOutput.fromJson(
              json['vocal_model_output'] as Map<String, dynamic>,
            )
          : null,
      processedAt: DateTime.tryParse(json['processed_at'] as String? ?? '') ??
          DateTime.now(),
      model: json['model'] as String? ?? 'uvr-mdxnet-9482',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'music_file_id': musicFileId,
      'stems': stems.map((stem) => stem.toJson()).toList(),
      'stem_timestamps':
          stemTimestamps.map((segment) => segment.toJson()).toList(),
      'structure_segments':
          structureSegments.map((segment) => segment.toJson()).toList(),
      if (vocalModelOutput != null)
        'vocal_model_output': vocalModelOutput!.toJson(),
      'processed_at': processedAt.toIso8601String(),
      'model': model,
    };
  }

  SeparationResult copyWith({
    String? musicFileId,
    List<TrackStem>? stems,
    List<Segment>? stemTimestamps,
    List<Segment>? structureSegments,
    VocalModelOutput? vocalModelOutput,
    DateTime? processedAt,
    String? model,
  }) {
    return SeparationResult(
      musicFileId: musicFileId ?? this.musicFileId,
      stems: stems ?? List<TrackStem>.from(this.stems),
      stemTimestamps: stemTimestamps ?? List<Segment>.from(this.stemTimestamps),
      structureSegments:
          structureSegments ?? List<Segment>.from(this.structureSegments),
      vocalModelOutput: vocalModelOutput ?? this.vocalModelOutput,
      processedAt: processedAt ?? this.processedAt,
      model: model ?? this.model,
    );
  }
}
