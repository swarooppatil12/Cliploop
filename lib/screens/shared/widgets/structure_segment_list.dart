import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/segment_labels.dart';
import '../../../core/utils/time_formatter.dart';
import '../../../models/segment.dart';

class StructureSegmentList extends StatelessWidget {
  const StructureSegmentList({
    super.key,
    required this.segments,
    required this.selectedSegmentId,
    required this.onSegmentTap,
  });

  final List<Segment> segments;
  final String? selectedSegmentId;
  final ValueChanged<Segment> onSegmentTap;

  @override
  Widget build(BuildContext context) {
    final markers = segments
        .where((segment) => segment.type != SegmentType.unknown)
        .toList()
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    final interludeCount = structureInterludeCount(markers);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step 4 — Prelude / Interlude / Postlude', style: AppTextStyles.headlineLarge),
        const SizedBox(height: 6),
        Text(
          interludeCount == 0
              ? '0 interludes found'
              : interludeCount == 1
                  ? '1 interlude found'
                  : '$interludeCount interludes found',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.segmentInterlude,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        const _StructureLegend(),
        const SizedBox(height: 16),
        if (markers.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Text(
              'No Prelude, Interlude, or Postlude detected in this song yet.',
              style: AppTextStyles.bodyMedium,
            ),
          )
        else
          ...markers.map(
            (segment) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SegmentRow(
                segment: segment,
                allSegments: markers,
                isSelected: segment.id == selectedSegmentId,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onSegmentTap(segment);
                },
              ),
            ),
          ),
        if (markers.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Tap a segment to play it — playback stops at the end of that section.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _StructureLegend extends StatelessWidget {
  const _StructureLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _LegendChip(type: SegmentType.prelude),
        _LegendChip(type: SegmentType.interlude),
        _LegendChip(type: SegmentType.postlude),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.type});

  final SegmentType type;

  Color get _color => switch (type) {
        SegmentType.prelude => AppColors.segmentPrelude,
        SegmentType.interlude => AppColors.segmentInterlude,
        SegmentType.postlude => AppColors.segmentPostlude,
        SegmentType.unknown => AppColors.textSecondary,
      };

  String get _label => switch (type) {
        SegmentType.prelude => 'Prelude',
        SegmentType.interlude => 'Interlude',
        SegmentType.postlude => 'Postlude',
        SegmentType.unknown => '',
      };

  String get _description => switch (type) {
        SegmentType.prelude => 'Opening instrumental section before vocals',
        SegmentType.interlude => 'Drums & beats break with no vocals',
        SegmentType.postlude => 'Closing instrumental section after vocals',
        SegmentType.unknown => '',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _label,
                style: AppTextStyles.labelSmall.copyWith(
                  color: _color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _description,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.segment,
    required this.allSegments,
    required this.isSelected,
    required this.onTap,
  });

  final Segment segment;
  final List<Segment> allSegments;
  final bool isSelected;
  final VoidCallback onTap;

  Color get _color => switch (segment.type) {
        SegmentType.prelude => AppColors.segmentPrelude,
        SegmentType.interlude => AppColors.segmentInterlude,
        SegmentType.postlude => AppColors.segmentPostlude,
        SegmentType.unknown => AppColors.textSecondary,
      };

  String get _label =>
      structureSegmentDisplayName(segment, allSegments);

  String? get _contentLabel {
    final label = segment.label;
    if (label == null || !label.contains(' · ')) {
      return null;
    }
    return label.split(' · ').skip(1).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected
                ? _color.withValues(alpha: 0.14)
                : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? _color : AppColors.surfaceBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label,
                        style: AppTextStyles.headlineMedium.copyWith(color: _color),
                      ),
                      if (_contentLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _contentLabel!,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(segment.timeRange, style: AppTextStyles.mono),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      TimeFormatter.formatDuration(segment.durationSeconds.round()),
                      style: AppTextStyles.bodyLarge,
                    ),
                    const SizedBox(height: 2),
                    Icon(
                      Icons.play_circle_outline_rounded,
                      color: isSelected ? _color : AppColors.textSecondary,
                      size: 22,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
