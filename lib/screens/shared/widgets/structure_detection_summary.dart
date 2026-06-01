import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/segment_labels.dart';
import '../../../models/segment.dart';

class StructureDetectionSummary extends StatelessWidget {
  const StructureDetectionSummary({
    super.key,
    required this.segments,
  });

  final List<Segment> segments;

  @override
  Widget build(BuildContext context) {
    final interludeCount = structureInterludeCount(segments);
    final summary = structureDetectionSummary(segments);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Detection result', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 8),
          Text(
            summary,
            style: AppTextStyles.bodyLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CountChip(
                label: 'Prelude',
                count: segments
                    .where((segment) => segment.type == SegmentType.prelude)
                    .length,
                color: AppColors.segmentPrelude,
              ),
              _CountChip(
                label: 'Interlude',
                count: interludeCount,
                color: AppColors.segmentInterlude,
                highlight: true,
              ),
              _CountChip(
                label: 'Postlude',
                count: segments
                    .where((segment) => segment.type == SegmentType.postlude)
                    .length,
                color: AppColors.segmentPostlude,
              ),
            ],
          ),
          if (interludeCount == 0) ...[
            const SizedBox(height: 10),
            Text(
              'No drum-break interludes were found in this song.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              interludeCount == 1
                  ? '1 interlude detected — tap it below to jump and listen.'
                  : '$interludeCount interludes detected — tap each one below to jump and listen.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
    required this.color,
    this.highlight = false,
  });

  final String label;
  final int count;
  final Color color;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: highlight ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: highlight ? 0.65 : 0.35),
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Text(
        '$count $label${count == 1 ? '' : 's'}',
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Segment? preferredStructureSegment(List<Segment> segments) {
  final interludes = segments
      .where((segment) => segment.type == SegmentType.interlude)
      .toList()
    ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

  if (interludes.isNotEmpty) {
    return interludes.first;
  }

  if (segments.isEmpty) {
    return null;
  }

  return segments.first;
}
