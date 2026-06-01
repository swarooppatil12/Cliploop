import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/time_formatter.dart';
import '../../../models/music_file.dart';

class FileCard extends StatelessWidget {
  const FileCard({
    super.key,
    required this.file,
    required this.onTap,
    required this.onDelete,
    this.isSelected = false,
    this.animationIndex = 0,
  });

  final MusicFile file;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool isSelected;
  final int animationIndex;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onDelete();
      },
      child: Container(
        width: 220,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryGreen.withValues(alpha: 0.08)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primaryGreen : AppColors.surfaceBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.audiotrack_rounded,
                  color: AppColors.primaryGreen,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.name,
                    style: AppTextStyles.headlineMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Remove from library',
                  onPressed: onDelete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: CustomPaint(
                painter: _MiniWaveformPainter(seed: file.id.hashCode),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  TimeFormatter.formatDuration(file.durationSeconds),
                  style: AppTextStyles.mono,
                ),
                Text(
                  DateFormat('dd MMM').format(file.receivedAt),
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(
          duration: 450.ms,
          curve: Curves.easeOutCubic,
          delay: (animationIndex * 80).ms,
        )
        .slideY(
          begin: 0.2,
          curve: Curves.easeOutCubic,
          delay: (animationIndex * 80).ms,
        );
  }
}

class _MiniWaveformPainter extends CustomPainter {
  _MiniWaveformPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final barWidth = 3.0;
    final gap = 2.0;
    final barCount = (size.width / (barWidth + gap)).floor().clamp(8, 40);
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (var i = 0; i < barCount; i++) {
      final normalized = random.nextDouble();
      final barHeight = (normalized * 0.75 + 0.15) * size.height;
      final x = i * (barWidth + gap);
      final y = (size.height - barHeight) / 2;

      paint.color = Color.lerp(
        AppColors.surfaceBorder,
        AppColors.primaryGreen,
        normalized,
      )!;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniWaveformPainter oldDelegate) {
    return oldDelegate.seed != seed;
  }
}
