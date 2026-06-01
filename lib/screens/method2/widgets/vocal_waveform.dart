import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/segment.dart';
import '../../method1/widgets/waveform_widget.dart';

class VocalWaveform extends StatefulWidget {
  const VocalWaveform({
    super.key,
    required this.waveformData,
    required this.audioPath,
    required this.durationSeconds,
    required this.position,
    required this.vocalRegions,
    required this.instrumentalRegions,
    required this.onSeek,
  });

  final List<double> waveformData;
  final String audioPath;
  final double durationSeconds;
  final Duration position;
  final List<Segment> vocalRegions;
  final List<Segment> instrumentalRegions;
  final ValueChanged<Duration> onSeek;

  @override
  State<VocalWaveform> createState() => _VocalWaveformState();
}

class _VocalWaveformState extends State<VocalWaveform> {
  bool _showInstrumental = false;

  @override
  Widget build(BuildContext context) {
    final activeRegions =
        _showInstrumental ? widget.instrumentalRegions : widget.vocalRegions;
    final highlightLabel =
        _showInstrumental ? 'Instrumental Regions' : 'Vocal Regions';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(highlightLabel, style: AppTextStyles.headlineMedium),
            ),
            Text(
              _showInstrumental ? 'Instrumentals' : 'Vocals',
              style: AppTextStyles.bodyMedium,
            ),
            Switch(
              value: _showInstrumental,
              activeThumbColor: AppColors.primaryGreen,
              onChanged: (value) => setState(() => _showInstrumental = value),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            WaveformWidget(
              waveformData: widget.waveformData,
              audioPath: widget.audioPath,
              durationSeconds: widget.durationSeconds,
              position: widget.position,
              onSeek: widget.onSeek,
              isMaster: true,
              height: 110,
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RegionHighlightPainter(
                    regions: activeRegions,
                    durationSeconds: widget.durationSeconds,
                    highlightColor: _showInstrumental
                        ? AppColors.primaryPurple
                        : AppColors.primaryGreen,
                    dimColor: AppColors.background.withValues(alpha: 0.45),
                    invertHighlight: _showInstrumental,
                    allRegions: widget.vocalRegions,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RegionHighlightPainter extends CustomPainter {
  _RegionHighlightPainter({
    required this.regions,
    required this.durationSeconds,
    required this.highlightColor,
    required this.dimColor,
    required this.invertHighlight,
    required this.allRegions,
  });

  final List<Segment> regions;
  final double durationSeconds;
  final Color highlightColor;
  final Color dimColor;
  final bool invertHighlight;
  final List<Segment> allRegions;

  @override
  void paint(Canvas canvas, Size size) {
    if (durationSeconds <= 0) {
      return;
    }

    if (invertHighlight) {
      for (final region in allRegions) {
        final startX = (region.startSeconds / durationSeconds) * size.width;
        final endX = (region.endSeconds / durationSeconds) * size.width;
        canvas.drawRect(
          Rect.fromLTRB(startX, 0, endX, size.height),
          Paint()..color = dimColor,
        );
      }
      return;
    }

    for (final region in regions) {
      final startX = (region.startSeconds / durationSeconds) * size.width;
      final endX = (region.endSeconds / durationSeconds) * size.width;
      canvas.drawRect(
        Rect.fromLTRB(startX, 0, endX, size.height),
        Paint()..color = highlightColor.withValues(alpha: 0.18),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RegionHighlightPainter oldDelegate) {
    return oldDelegate.regions != regions ||
        oldDelegate.durationSeconds != durationSeconds ||
        oldDelegate.invertHighlight != invertHighlight;
  }
}
