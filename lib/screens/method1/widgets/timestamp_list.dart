import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/segment.dart';

class TimestampList extends StatelessWidget {
  const TimestampList({
    super.key,
    required this.timestamps,
    required this.structureSegments,
    required this.onSeek,
  });

  final List<Segment> timestamps;
  final List<Segment> structureSegments;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    if (timestamps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No stem activity timestamps yet.',
          style: AppTextStyles.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: timestamps.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final segment = timestamps[index];
        final structureType = _structureTypeForSegment(segment);
        final activity = segment.confidence.clamp(0.0, 1.0);
        final label = segment.label ?? 'Stem active';

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.lightImpact();
            onSeek(Duration(milliseconds: (segment.startSeconds * 1000).round()));
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('[${segment.timeRange}]', style: AppTextStyles.mono),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(label, style: AppTextStyles.bodyLarge),
                    ),
                    if (structureType != null)
                      _StructureBadge(type: structureType),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: activity,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceBorder,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  SegmentType? _structureTypeForSegment(Segment segment) {
    for (final structure in structureSegments) {
      if (structure.type == SegmentType.unknown) {
        continue;
      }
      final overlaps = segment.startSeconds < structure.endSeconds &&
          segment.endSeconds > structure.startSeconds;
      if (overlaps) {
        return structure.type;
      }
    }
    return null;
  }
}

class _StructureBadge extends StatelessWidget {
  const _StructureBadge({required this.type});

  final SegmentType type;

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      SegmentType.prelude => AppColors.segmentPrelude,
      SegmentType.interlude => AppColors.segmentInterlude,
      SegmentType.postlude => AppColors.segmentPostlude,
      SegmentType.unknown => AppColors.textSecondary,
    };
    final label = switch (type) {
      SegmentType.prelude => 'PRELUDE',
      SegmentType.interlude => 'INTERLUDE',
      SegmentType.postlude => 'POSTLUDE',
      SegmentType.unknown => 'UNKNOWN',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        '● $label',
        style: AppTextStyles.labelSmall.copyWith(color: color),
      ),
    );
  }
}
