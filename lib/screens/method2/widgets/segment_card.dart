import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/time_formatter.dart';
import '../../../models/segment.dart';
import '../../../widgets/common/gradient_button.dart';

class SegmentCard extends StatefulWidget {
  const SegmentCard({
    super.key,
    required this.segment,
    required this.loopEnabled,
    required this.onPlay,
    required this.onLoopChanged,
  });

  final Segment segment;
  final bool loopEnabled;
  final VoidCallback onPlay;
  final ValueChanged<bool> onLoopChanged;

  @override
  State<SegmentCard> createState() => _SegmentCardState();
}

class _SegmentCardState extends State<SegmentCard> {
  Color get _color {
    return switch (widget.segment.type) {
      SegmentType.prelude => AppColors.segmentPrelude,
      SegmentType.interlude => AppColors.segmentInterlude,
      SegmentType.postlude => AppColors.segmentPostlude,
      SegmentType.unknown => AppColors.textSecondary,
    };
  }

  String get _label {
    return switch (widget.segment.type) {
      SegmentType.prelude => 'PRELUDE',
      SegmentType.interlude => 'INTERLUDE',
      SegmentType.postlude => 'POSTLUDE',
      SegmentType.unknown => 'UNKNOWN',
    };
  }

  @override
  Widget build(BuildContext context) {
    final confidence = widget.segment.confidence.clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _color),
            ),
            child: Text(
              _label,
              style: AppTextStyles.headlineMedium.copyWith(color: _color),
            ),
          ),
          const SizedBox(height: 14),
          Text(widget.segment.timeRange, style: AppTextStyles.mono),
          const SizedBox(height: 6),
          Text(
            'Duration: ${TimeFormatter.formatDuration(widget.segment.durationSeconds.round())}',
            style: AppTextStyles.bodyLarge,
          ),
          const SizedBox(height: 12),
          _Badge(
            icon: widget.segment.hasVocals
                ? Icons.mic_rounded
                : Icons.music_note_rounded,
            label: widget.segment.hasVocals ? 'Contains Vocals' : 'Instrumental',
            color: widget.segment.hasVocals
                ? AppColors.primaryGreen
                : AppColors.textSecondary,
          ),
          const SizedBox(height: 14),
          Text(
            'Confidence: ${(confidence * 100).round()}%',
            style: AppTextStyles.bodyLarge,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: confidence,
              minHeight: 8,
              backgroundColor: AppColors.surfaceBorder,
              color: _color,
            ),
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: 'Play this segment',
            icon: Icons.play_arrow_rounded,
            colors: [_color, AppColors.primaryPurple],
            onPressed: widget.onPlay,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('Loop this segment', style: AppTextStyles.bodyLarge),
              ),
              Switch(
                value: widget.loopEnabled,
                activeThumbColor: AppColors.primaryGreen,
                onChanged: widget.onLoopChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.bodyMedium.copyWith(color: color)),
        ],
      ),
    );
  }
}
