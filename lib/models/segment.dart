enum SegmentType { prelude, interlude, postlude, unknown }

extension SegmentTypeJson on SegmentType {
  String toJson() => name;

  static SegmentType fromJson(String value) {
    return SegmentType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => SegmentType.unknown,
    );
  }
}

String _fmtPrecise(double seconds) {
  final total = seconds.floor();
  final minutes = total ~/ 60;
  final secs = total % 60;
  final millis = ((seconds - total) * 1000).round();
  return '${minutes.toString().padLeft(2, '0')}:'
      '${secs.toString().padLeft(2, '0')}.'
      '${millis.toString().padLeft(3, '0')}';
}

class Segment {
  final String id;
  final SegmentType type;
  final double startSeconds;
  final double endSeconds;
  final bool hasVocals;
  final double confidence;
  final String? label;

  const Segment({
    required this.id,
    required this.type,
    required this.startSeconds,
    required this.endSeconds,
    required this.hasVocals,
    required this.confidence,
    this.label,
  });

  double get durationSeconds => endSeconds - startSeconds;

  String get timeRange =>
      '${_fmtPrecise(startSeconds)} → ${_fmtPrecise(endSeconds)}';

  factory Segment.fromJson(Map<String, dynamic> json) {
    final start = (json['start_seconds'] as num?)?.toDouble() ??
        (json['start'] as num?)?.toDouble() ??
        0;
    final end = (json['end_seconds'] as num?)?.toDouble() ??
        (json['end'] as num?)?.toDouble() ??
        0;
    final typeValue = (json['type'] as String?) ?? 'unknown';

    return Segment(
      id: json['id'] as String? ?? '${typeValue}_${start}_$end',
      type: SegmentTypeJson.fromJson(typeValue),
      startSeconds: start,
      endSeconds: end,
      hasVocals: json['has_vocals'] as bool? ??
          json['hasVocals'] as bool? ??
          false,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      label: json['label'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toJson(),
      'start_seconds': startSeconds,
      'end_seconds': endSeconds,
      'has_vocals': hasVocals,
      'confidence': confidence,
      'label': label,
    };
  }

  Segment copyWith({
    String? id,
    SegmentType? type,
    double? startSeconds,
    double? endSeconds,
    bool? hasVocals,
    double? confidence,
    String? label,
  }) {
    return Segment(
      id: id ?? this.id,
      type: type ?? this.type,
      startSeconds: startSeconds ?? this.startSeconds,
      endSeconds: endSeconds ?? this.endSeconds,
      hasVocals: hasVocals ?? this.hasVocals,
      confidence: confidence ?? this.confidence,
      label: label ?? this.label,
    );
  }
}
