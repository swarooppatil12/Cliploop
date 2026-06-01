class MusicFile {
  final String id;
  final String name;
  final String path;
  final int durationSeconds;
  final int fileSizeBytes;
  final DateTime receivedAt;
  final String? thumbnailPath;

  const MusicFile({
    required this.id,
    required this.name,
    required this.path,
    required this.durationSeconds,
    required this.fileSizeBytes,
    required this.receivedAt,
    this.thumbnailPath,
  });

  factory MusicFile.fromJson(Map<String, dynamic> json) {
    return MusicFile(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      durationSeconds: json['duration_seconds'] as int,
      fileSizeBytes: json['file_size_bytes'] as int,
      receivedAt: DateTime.parse(json['received_at'] as String),
      thumbnailPath: json['thumbnail_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'duration_seconds': durationSeconds,
      'file_size_bytes': fileSizeBytes,
      'received_at': receivedAt.toIso8601String(),
      'thumbnail_path': thumbnailPath,
    };
  }

  MusicFile copyWith({
    String? id,
    String? name,
    String? path,
    int? durationSeconds,
    int? fileSizeBytes,
    DateTime? receivedAt,
    String? thumbnailPath,
  }) {
    return MusicFile(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      receivedAt: receivedAt ?? this.receivedAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }
}
