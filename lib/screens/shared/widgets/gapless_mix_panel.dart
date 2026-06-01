import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/time_formatter.dart';
import '../../../services/gapless_mix_service.dart';

class GaplessMixPanel extends StatelessWidget {
  const GaplessMixPanel({
    super.key,
    required this.interludeCount,
    required this.isBuilding,
    required this.lastExport,
    required this.onCreate,
    required this.onPlay,
    required this.onSave,
  });

  final int interludeCount;
  final bool isBuilding;
  final GaplessMixResult? lastExport;
  final VoidCallback onCreate;
  final VoidCallback? onPlay;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final hasExport = lastExport != null;

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
          Text('Gapless mix', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 6),
          Text(
            interludeCount == 0
                ? 'No interludes to remove — build still combines vocal + instrumental stems.'
                : 'Combines vocal + instrumental, crossfades over $interludeCount interlude gap(s), and creates a shorter track.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (hasExport) ...[
            const SizedBox(height: 10),
            Text(
              'Original ${TimeFormatter.formatDuration(lastExport!.originalDurationSeconds.round())} → '
              'New ${TimeFormatter.formatDuration(lastExport!.newDurationSeconds.round())} '
              '(${lastExport!.removedSeconds.toStringAsFixed(1)}s removed)',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: isBuilding
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        onCreate();
                      },
                icon: isBuilding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.merge_rounded),
                label: Text(isBuilding ? 'Building…' : 'Create gapless mix'),
              ),
              if (hasExport && onPlay != null)
                OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onPlay!();
                  },
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Play'),
                ),
              if (hasExport && onSave != null)
                OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onSave!();
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Save WAV'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
