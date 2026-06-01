enum StemType { vocals, accompaniment, drums, bass, other, piano, guitar }

extension StemTypeJson on StemType {
  String toJson() => name;

  static StemType fromJson(String value) {
    return StemType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => StemType.other,
    );
  }
}

class TrackStem {
  final String id;
  final StemType type;
  final String audioPath;
  final double durationSeconds;
  final List<double> waveformData;
  bool isMuted;
  double volume;

  TrackStem({
    required this.id,
    required this.type,
    required this.audioPath,
    required this.durationSeconds,
    required this.waveformData,
    this.isMuted = false,
    this.volume = 1.0,
  });

  factory TrackStem.fromJson(Map<String, dynamic> json) {
    final typeValue = (json['type'] as String?) ?? 'other';

    return TrackStem(
      id: json['id'] as String? ?? typeValue,
      type: StemTypeJson.fromJson(typeValue),
      audioPath: json['audio_path'] as String? ??
          json['path'] as String? ??
          '',
      durationSeconds:
          (json['duration_seconds'] as num?)?.toDouble() ?? 0,
      waveformData: (json['waveform_data'] as List<dynamic>?)
              ?.map((value) => (value as num).toDouble())
              .toList() ??
          const [],
      isMuted: json['is_muted'] as bool? ?? false,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toJson(),
      'audio_path': audioPath,
      'duration_seconds': durationSeconds,
      'waveform_data': waveformData,
      'is_muted': isMuted,
      'volume': volume,
    };
  }

  TrackStem copyWith({
    String? id,
    StemType? type,
    String? audioPath,
    double? durationSeconds,
    List<double>? waveformData,
    bool? isMuted,
    double? volume,
  }) {
    return TrackStem(
      id: id ?? this.id,
      type: type ?? this.type,
      audioPath: audioPath ?? this.audioPath,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      waveformData: waveformData ?? List<double>.from(this.waveformData),
      isMuted: isMuted ?? this.isMuted,
      volume: volume ?? this.volume,
    );
  }
}
