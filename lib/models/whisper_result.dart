import 'segment.dart';
import 'track_stem.dart';
import 'vocal_model_output.dart';

class WhisperResult {
  final String musicFileId;
  final List<TrackStem> stems;
  final List<Segment> segments;
  final List<Segment> vocalTimestamps;
  final List<Segment> nonVocalSegments;
  final VocalModelOutput? vocalModelOutput;
  final String? vocalSeparationModel;
  final String? separationModel;
  final DateTime processedAt;

  const WhisperResult({
    required this.musicFileId,
    this.stems = const [],
    required this.segments,
    required this.vocalTimestamps,
    required this.nonVocalSegments,
    this.vocalModelOutput,
    this.vocalSeparationModel,
    this.separationModel,
    required this.processedAt,
  });

  factory WhisperResult.fromJson(Map<String, dynamic> json) {
    return WhisperResult(
      musicFileId: json['music_file_id'] as String? ?? '',
      stems: (json['stems'] as List<dynamic>?)
              ?.map((item) => TrackStem.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      segments: (json['segments'] as List<dynamic>?)
              ?.map((item) => Segment.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      vocalTimestamps: (json['vocal_timestamps'] as List<dynamic>?)
              ?.map((item) => Segment.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      nonVocalSegments: (json['non_vocal_segments'] as List<dynamic>?)
              ?.map((item) => Segment.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      vocalModelOutput: json['vocal_model_output'] != null
          ? VocalModelOutput.fromJson(
              json['vocal_model_output'] as Map<String, dynamic>,
            )
          : null,
      vocalSeparationModel: json['vocal_separation_model'] as String?,
      separationModel: json['separation_model'] as String?,
      processedAt: DateTime.tryParse(json['processed_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'music_file_id': musicFileId,
      'stems': stems.map((stem) => stem.toJson()).toList(),
      'segments': segments.map((segment) => segment.toJson()).toList(),
      'vocal_timestamps':
          vocalTimestamps.map((segment) => segment.toJson()).toList(),
      'non_vocal_segments':
          nonVocalSegments.map((segment) => segment.toJson()).toList(),
      if (vocalModelOutput != null)
        'vocal_model_output': vocalModelOutput!.toJson(),
      if (vocalSeparationModel != null)
        'vocal_separation_model': vocalSeparationModel,
      if (separationModel != null) 'separation_model': separationModel,
      'processed_at': processedAt.toIso8601String(),
    };
  }

  WhisperResult copyWith({
    String? musicFileId,
    List<TrackStem>? stems,
    List<Segment>? segments,
    List<Segment>? vocalTimestamps,
    List<Segment>? nonVocalSegments,
    VocalModelOutput? vocalModelOutput,
    String? vocalSeparationModel,
    String? separationModel,
    DateTime? processedAt,
  }) {
    return WhisperResult(
      musicFileId: musicFileId ?? this.musicFileId,
      stems: stems ?? List<TrackStem>.from(this.stems),
      segments: segments ?? List<Segment>.from(this.segments),
      vocalTimestamps:
          vocalTimestamps ?? List<Segment>.from(this.vocalTimestamps),
      nonVocalSegments:
          nonVocalSegments ?? List<Segment>.from(this.nonVocalSegments),
      vocalModelOutput: vocalModelOutput ?? this.vocalModelOutput,
      vocalSeparationModel:
          vocalSeparationModel ?? this.vocalSeparationModel,
      separationModel: separationModel ?? this.separationModel,
      processedAt: processedAt ?? this.processedAt,
    );
  }
}
