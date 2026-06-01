import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/segment.dart';

class SegmentControls extends StatelessWidget {
  const SegmentControls({
    super.key,
    required this.currentSegment,
    required this.isPlaying,
    required this.segmentProgress,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onExport,
  });

  final Segment? currentSegment;
  final bool isPlaying;
  final double segmentProgress;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onExport;

  Color _colorFor(Segment? segment) {
    if (segment == null) {
      return AppColors.textSecondary;
    }
    return switch (segment.type) {
      SegmentType.prelude => AppColors.segmentPrelude,
      SegmentType.interlude => AppColors.segmentInterlude,
      SegmentType.postlude => AppColors.segmentPostlude,
      SegmentType.unknown => AppColors.textSecondary,
    };
  }

  String _labelFor(Segment? segment) {
    if (segment == null) {
      return 'No segment selected';
    }
    return switch (segment.type) {
      SegmentType.prelude => 'PRELUDE',
      SegmentType.interlude => 'INTERLUDE',
      SegmentType.postlude => 'POSTLUDE',
      SegmentType.unknown => 'SEGMENT',
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(currentSegment);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _labelFor(currentSegment),
            style: AppTextStyles.displayMedium.copyWith(
              fontSize: 22,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: segmentProgress.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.surfaceBorder,
              color: color,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onPrevious();
                },
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onPlayPause();
                },
                icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                iconSize: 44,
                color: color,
              ),
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onNext();
                },
                icon: const Icon(Icons.skip_next_rounded),
              ),
              IconButton(
                onPressed: onExport,
                icon: const Icon(Icons.file_download_outlined),
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
