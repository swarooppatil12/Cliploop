import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/time_formatter.dart';
import '../../../services/vocal_silence_service.dart';

class VocalSilencePanel extends StatelessWidget {
  const VocalSilencePanel({
    super.key,
    required this.summary,
    required this.durationSeconds,
  });

  final VocalSilenceSummary summary;
  final double durationSeconds;

  @override
  Widget build(BuildContext context) {
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
          Text(
            'Vocal silence regions ≥ 10s only',
            style: AppTextStyles.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Spans where the vocal stem is almost silent for at least 10 seconds.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatChip(
                label: 'Regions (≥ 10s)',
                value: '${summary.regionCount}',
              ),
              _StatChip(
                label: 'Total quiet time',
                value: TimeFormatter.formatPrecise(summary.totalQuietSeconds),
              ),
              _StatChip(
                label: '% of song (quiet)',
                value: '${summary.percentQuiet}%',
              ),
              _StatChip(
                label: 'Strictly silent',
                value:
                    '${TimeFormatter.formatPrecise(summary.totalSilentSeconds)} (${summary.percentStrictlySilent}%)',
                highlight: true,
              ),
              _StatChip(
                label: 'RMS threshold',
                value: summary.threshold.toString(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SilenceTimeline(summary: summary, durationSeconds: durationSeconds),
          if (summary.regions.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'No vocal silence regions ≥ 10 seconds detected.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            _SilenceTable(regions: summary.regions),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight ? const Color(0xFFEF4444) : AppColors.surfaceBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }
}

class _SilenceTimeline extends StatelessWidget {
  const _SilenceTimeline({
    required this.summary,
    required this.durationSeconds,
  });

  final VocalSilenceSummary summary;
  final double durationSeconds;

  @override
  Widget build(BuildContext context) {
    if (durationSeconds <= 0) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 14,
        width: double.infinity,
        child: CustomPaint(
          painter: _SilenceTimelinePainter(
            regions: summary.regions,
            durationSeconds: durationSeconds,
          ),
        ),
      ),
    );
  }
}

class _SilenceTimelinePainter extends CustomPainter {
  _SilenceTimelinePainter({
    required this.regions,
    required this.durationSeconds,
  });

  final List<VocalSilenceRegion> regions;
  final double durationSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppColors.surfaceBorder,
    );

    for (final region in regions) {
      final left = (region.startSeconds / durationSeconds) * size.width;
      final width =
          ((region.endSeconds - region.startSeconds) / durationSeconds) *
              size.width;
      final color = region.level == VocalSilenceLevel.silent
          ? const Color(0xFFEF4444)
          : const Color(0xFFFB923C);
      canvas.drawRect(
        Rect.fromLTWH(left, 0, width.clamp(1, size.width), size.height),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SilenceTimelinePainter oldDelegate) => true;
}

class _SilenceTable extends StatelessWidget {
  const _SilenceTable({required this.regions});

  final List<VocalSilenceRegion> regions;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textSecondary,
        ),
        dataTextStyle: AppTextStyles.bodyMedium,
        columns: const [
          DataColumn(label: Text('#')),
          DataColumn(label: Text('Start')),
          DataColumn(label: Text('End')),
          DataColumn(label: Text('Duration')),
          DataColumn(label: Text('% of song')),
          DataColumn(label: Text('Level')),
        ],
        rows: [
          for (var i = 0; i < regions.length; i++)
            DataRow(
              cells: [
                DataCell(Text('${i + 1}')),
                DataCell(Text(TimeFormatter.formatPrecise(regions[i].startSeconds))),
                DataCell(Text(TimeFormatter.formatPrecise(regions[i].endSeconds))),
                DataCell(Text(TimeFormatter.formatPrecise(regions[i].durationSeconds))),
                DataCell(Text('${regions[i].percentOfSong}%')),
                DataCell(
                  Text(
                    '${regions[i].level.name}'
                    '${regions[i].avgRms != 0 ? ' (rms ${regions[i].avgRms})' : ''}',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
