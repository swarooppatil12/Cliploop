import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/time_formatter.dart';
import '../../../models/segment.dart';
import '../../../models/vocal_model_output.dart';

class VocalDetectionList extends StatelessWidget {
  const VocalDetectionList({
    super.key,
    required this.vocalOutput,
    this.onSegmentTap,
  });

  final VocalModelOutput vocalOutput;
  final ValueChanged<Segment>? onSegmentTap;

  @override
  Widget build(BuildContext context) {
    final sortedVocal = List<Segment>.from(vocalOutput.vocalTimestamps)
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    final sortedOpposite =
        List<Segment>.from(vocalOutput.nonVocalOppositeSegments)
          ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    final sortedParts = List<Segment>.from(vocalOutput.nonVocalPartSegments)
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Detection pipeline', style: AppTextStyles.headlineLarge),
        const SizedBox(height: 6),
        Text(
          '1 Vocals → 2 Non-vocal opposite → 3 Parts → 4 Prelude / Interlude / Postlude',
          style: AppTextStyles.bodyMedium,
        ),
        const SizedBox(height: 20),
        _PipelineStep(
          step: 1,
          title: 'Vocals detected',
          subtitle: 'Regions where the vocal model finds singing',
          count: sortedVocal.length,
          color: AppColors.primaryGreen,
          segments: sortedVocal,
          badge: 'VOCAL',
          emptyMessage: 'No vocal regions found on the vocals stem.',
          onSegmentTap: onSegmentTap,
        ),
        const SizedBox(height: 20),
        _PipelineStep(
          step: 2,
          title: 'Non-vocal (opposite)',
          subtitle: 'Everything that is not vocal — inverse of step 1',
          count: sortedOpposite.length,
          color: AppColors.primaryPurple,
          segments: sortedOpposite,
          badge: 'NON-VOCAL',
          emptyMessage: 'No non-vocal regions — vocals cover the full song.',
          onSegmentTap: onSegmentTap,
        ),
        const SizedBox(height: 20),
        _PipelineStep(
          step: 3,
          title: 'Non-vocal parts',
          subtitle: 'Distinct parts used to label Prelude / Interlude / Postlude',
          count: sortedParts.length,
          color: AppColors.accentOrange,
          segments: sortedParts,
          badgeBuilder: (segment) =>
              (segment.label ?? 'part').toUpperCase().replaceAll(' ', '-'),
          emptyMessage: 'No non-vocal parts long enough to map structure.',
          onSegmentTap: onSegmentTap,
        ),
      ],
    );
  }
}

class RawModelOutputPanel extends StatefulWidget {
  const RawModelOutputPanel({super.key, required this.rawLog});

  final String rawLog;

  @override
  State<RawModelOutputPanel> createState() => _RawModelOutputPanelState();
}

class _RawModelOutputPanelState extends State<RawModelOutputPanel> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.rawLog.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text('Step 4 — Raw model log', style: AppTextStyles.headlineMedium),
                const Spacer(),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: SelectableText(
              widget.rawLog,
              style: AppTextStyles.mono.copyWith(
                fontSize: 11,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.rawLog));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Raw log copied')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy log'),
            ),
          ),
        ],
      ],
    );
  }
}

class _PipelineStep extends StatelessWidget {
  const _PipelineStep({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.color,
    required this.segments,
    required this.emptyMessage,
    this.badge = '',
    this.badgeBuilder,
    this.onSegmentTap,
  });

  final int step;
  final String title;
  final String subtitle;
  final int count;
  final Color color;
  final List<Segment> segments;
  final String badge;
  final String Function(Segment segment)? badgeBuilder;
  final String emptyMessage;
  final ValueChanged<Segment>? onSegmentTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$step',
                style: AppTextStyles.labelSmall.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.headlineMedium),
                  Text(subtitle, style: AppTextStyles.bodyMedium),
                ],
              ),
            ),
            Text('$count', style: AppTextStyles.mono.copyWith(color: color)),
          ],
        ),
        const SizedBox(height: 10),
        if (segments.isEmpty)
          _EmptyHint(message: emptyMessage)
        else
          ...segments.map(
            (segment) => _TimestampRow(
              segment: segment,
              accentColor: color,
              badge: badgeBuilder?.call(segment) ?? badge,
              onTap: onSegmentTap == null
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      onSegmentTap!(segment);
                    },
            ),
          ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Text(message, style: AppTextStyles.bodyMedium),
    );
  }
}

class _TimestampRow extends StatelessWidget {
  const _TimestampRow({
    required this.segment,
    required this.accentColor,
    required this.badge,
    this.onTap,
  });

  final Segment segment;
  final Color accentColor;
  final String badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(segment.timeRange, style: AppTextStyles.mono),
                  ),
                  Text(
                    TimeFormatter.formatDuration(
                      segment.durationSeconds.round(),
                    ),
                    style: AppTextStyles.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
