import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/time_formatter.dart';
import '../../../models/music_file.dart';
import '../../../providers/music_provider.dart';

/// Fixed-height upload card — border always matches the box (no inner scroll).
class UploadZone extends StatefulWidget {
  const UploadZone({super.key});

  static const double cardHeight = 212;
  static const double borderRadius = 22;
  static const double borderWidth = 2;

  @override
  State<UploadZone> createState() => _UploadZoneState();
}

class _UploadZoneState extends State<UploadZone>
    with SingleTickerProviderStateMixin {
  late final AnimationController _borderController;

  @override
  void initState() {
    super.initState();
    _borderController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _borderController.dispose();
    super.dispose();
  }

  Future<void> _pickFile(BuildContext context) async {
    final provider = context.read<MusicProvider>();
    if (provider.isProcessing) {
      return;
    }

    final previousId = provider.selectedFile?.id;
    try {
      await provider.pickAndLoadFile();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import audio: $error')),
      );
      return;
    }

    if (!context.mounted) {
      return;
    }

    final selected = provider.selectedFile;
    if (selected != null && selected.id != previousId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved to your library. Use Song Structure or Vocals below to analyse.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        final selectedFile = provider.selectedFile;
        final isProcessing = provider.isProcessing;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: GestureDetector(
            onTap: isProcessing ? null : () => _pickFile(context),
            child: SizedBox(
              height: UploadZone.cardHeight,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _borderController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _RotatingDashedBorderPainter(
                      progress: _borderController.value,
                      radius: UploadZone.borderRadius,
                      strokeWidth: UploadZone.borderWidth,
                    ),
                    child: child,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(UploadZone.borderWidth + 1),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(
                        UploadZone.borderRadius - 2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 64,
                            child: FittedBox(
                              child: _buildCenterVisual(
                                isProcessing: isProcessing,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: selectedFile == null
                                  ? const _EmptyUploadCopy()
                                  : _SelectedUploadCopy(file: selectedFile),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        )
            .animate()
            .fadeIn(duration: 500.ms, curve: Curves.easeOutCubic)
            .slideY(begin: 0.12, curve: Curves.easeOutCubic);
      },
    );
  }

  Widget _buildCenterVisual({required bool isProcessing}) {
    if (isProcessing) {
      return const SizedBox(
        width: 56,
        height: 56,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: AppColors.primaryGreen,
        ),
      );
    }

    return SizedBox(
      width: 64,
      height: 64,
      child: Lottie.network(
        'https://lottie.host/0c0f6f42-9337-4e64-8788-0e8367b4f725/7f3JqC6K3R.json',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(
            Icons.music_note_rounded,
            size: 48,
            color: AppColors.primaryGreen,
          );
        },
      ),
    );
  }
}

class _EmptyUploadCopy extends StatelessWidget {
  const _EmptyUploadCopy();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Tap to upload audio',
          style: AppTextStyles.headlineLarge.copyWith(fontSize: 18),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Share from WhatsApp or email, or pick a file',
          style: AppTextStyles.bodyMedium.copyWith(fontSize: 12, height: 1.3),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          'Then choose Song Structure or Vocals below',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.primaryPurple.withValues(alpha: 0.9),
            fontSize: 11,
            height: 1.3,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _SelectedUploadCopy extends StatelessWidget {
  const _SelectedUploadCopy({required this.file});

  final MusicFile file;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          file.name,
          style: AppTextStyles.headlineLarge.copyWith(fontSize: 17),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '${TimeFormatter.formatDuration(file.durationSeconds)} · '
          '${TimeFormatter.formatFileSize(file.fileSizeBytes)}',
          style: AppTextStyles.mono.copyWith(fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: AppColors.primaryGreen.withValues(alpha: 0.9),
              size: 16,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Ready — pick a method below',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RotatingDashedBorderPainter extends CustomPainter {
  _RotatingDashedBorderPainter({
    required this.progress,
    required this.radius,
    required this.strokeWidth,
  });

  final double progress;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final half = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      half,
      half,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    final gradient = SweepGradient(
      center: Alignment.center,
      startAngle: progress * 2 * math.pi,
      colors: const [
        AppColors.primaryGreen,
        AppColors.primaryPurple,
        AppColors.accentPink,
        AppColors.accentOrange,
        AppColors.primaryGreen,
      ],
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      const dashLength = 11.0;
      const gapLength = 7.0;
      var distance = 0.0;

      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RotatingDashedBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
