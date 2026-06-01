import '../../models/segment.dart';

/// User-facing name for a structure marker (Prelude, Interlude 1, Postlude, …).
String structureSegmentDisplayName(
  Segment segment,
  List<Segment> structureSegments,
) {
  return switch (segment.type) {
    SegmentType.prelude => 'Prelude',
    SegmentType.postlude => 'Postlude',
    SegmentType.interlude => _interludeDisplayName(segment, structureSegments),
    SegmentType.unknown => segment.label ?? 'Segment',
  };
}

String _interludeDisplayName(
  Segment segment,
  List<Segment> structureSegments,
) {
  final interludes = structureSegments
      .where((item) => item.type == SegmentType.interlude)
      .toList()
    ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

  final index = interludes.indexWhere((item) => item.id == segment.id);
  if (index < 0) {
    return 'Interlude';
  }

  return 'Interlude ${index + 1}';
}

int structureInterludeCount(List<Segment> structureSegments) {
  return structureSegments
      .where((item) => item.type == SegmentType.interlude)
      .length;
}

String structureDetectionSummary(List<Segment> structureSegments) {
  final preludeCount = structureSegments
      .where((item) => item.type == SegmentType.prelude)
      .length;
  final interludeCount = structureInterludeCount(structureSegments);
  final postludeCount = structureSegments
      .where((item) => item.type == SegmentType.postlude)
      .length;

  final parts = <String>[];
  if (preludeCount > 0) {
    parts.add('$preludeCount Prelude');
  }
  parts.add(
    interludeCount == 1 ? '1 Interlude' : '$interludeCount Interludes',
  );
  if (postludeCount > 0) {
    parts.add('$postludeCount Postlude');
  }

  return parts.join(' · ');
}

/// Short label for compact UI (timeline blocks).
String structureSegmentShortName(
  Segment segment,
  List<Segment> structureSegments,
) {
  return switch (segment.type) {
    SegmentType.prelude => 'Prelude',
    SegmentType.postlude => 'Postlude',
    SegmentType.interlude => _interludeShortName(segment, structureSegments),
    SegmentType.unknown => '',
  };
}

String _interludeShortName(
  Segment segment,
  List<Segment> structureSegments,
) {
  final interludes = structureSegments
      .where((item) => item.type == SegmentType.interlude)
      .toList()
    ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

  final index = interludes.indexWhere((item) => item.id == segment.id);
  if (index < 0) {
    return 'Int';
  }

  return 'Int ${index + 1}';
}
