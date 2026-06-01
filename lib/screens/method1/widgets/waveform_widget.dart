import 'dart:async';
import 'dart:math' as math;

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/time_formatter.dart';
import '../../../models/segment.dart';

class WaveformWidget extends StatefulWidget {
  const WaveformWidget({
    super.key,
    required this.waveformData,
    required this.durationSeconds,
    required this.position,
    required this.onSeek,
    this.audioPath,
    this.waveColor = AppColors.primaryGreen,
    this.isMaster = false,
    this.structureSegments = const [],
    this.height = 96,
    this.showTimeMarkers = true,
  });

  final List<double> waveformData;
  final String? audioPath;
  final double durationSeconds;
  final Duration position;
  final ValueChanged<Duration> onSeek;
  final Color waveColor;
  final bool isMaster;
  final List<Segment> structureSegments;
  final double height;
  final bool showTimeMarkers;

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget> {
  late final PlayerController _controller;
  StreamSubscription<int>? _positionSubscription;
  bool _prepared = false;

  @override
  void initState() {
    super.initState();
    _controller = PlayerController();
    _prepareController();
  }

  Future<void> _prepareController() async {
    final path = widget.audioPath;
    if (path != null && path.isNotEmpty) {
      try {
        await _controller.preparePlayer(
          path: path,
          shouldExtractWaveform: widget.waveformData.isEmpty,
        );
      } catch (_) {
        // Fall back to provided waveform data only.
      }
    }
    if (mounted) {
      setState(() => _prepared = true);
    }
  }

  @override
  void didUpdateWidget(covariant WaveformWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      final ms = widget.position.inMilliseconds;
      unawaited(_controller.seekTo(ms));
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    if (widget.durationSeconds <= 0) {
      return;
    }
    final ratio = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final target = Duration(
      milliseconds: (widget.durationSeconds * 1000 * ratio).round(),
    );
    widget.onSeek(target);
  }

  @override
  Widget build(BuildContext context) {
    if (!_prepared && widget.waveformData.isEmpty) {
      return Shimmer.fromColors(
        baseColor: AppColors.surfaceBorder,
        highlightColor: AppColors.surfaceElevated,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    final waveStyle = PlayerWaveStyle(
      fixedWaveColor: widget.waveColor.withValues(alpha: 0.35),
      liveWaveColor: widget.isMaster
          ? AppColors.primaryGreen
          : widget.waveColor,
      seekLineColor: AppColors.textPrimary,
      showSeekLine: true,
      spacing: widget.isMaster ? 4 : 3,
      waveThickness: widget.isMaster ? 3 : 2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTimeMarkers) _TimeMarkers(durationSeconds: widget.durationSeconds),
        if (widget.showTimeMarkers) const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTapUp: (details) => _handleTap(details, constraints),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  if (widget.isMaster && widget.structureSegments.isNotEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _StructureBandPainter(
                          segments: widget.structureSegments,
                          durationSeconds: widget.durationSeconds,
                        ),
                      ),
                    ),
                  AudioFileWaveforms(
                    size: Size(constraints.maxWidth, widget.height),
                    playerController: _controller,
                    waveformData: widget.waveformData,
                    enableSeekGesture: false,
                    waveformType: WaveformType.fitWidth,
                    playerWaveStyle: waveStyle,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                  ),
                  if (widget.durationSeconds > 0)
                    Positioned(
                      left: constraints.maxWidth *
                          (widget.position.inMilliseconds /
                              (widget.durationSeconds * 1000).clamp(1, double.infinity)),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        color: AppColors.textPrimary.withValues(alpha: 0.9),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TimeMarkers extends StatelessWidget {
  const _TimeMarkers({required this.durationSeconds});

  final double durationSeconds;

  @override
  Widget build(BuildContext context) {
    final markers = <int>[0];
    if (durationSeconds > 30) {
      markers.add((durationSeconds / 2).round());
    }
    markers.add(durationSeconds.round());

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: markers
          .map(
            (value) => Text(
              TimeFormatter.formatDuration(value),
              style: AppTextStyles.labelSmall,
            ),
          )
          .toList(),
    );
  }
}

class _StructureBandPainter extends CustomPainter {
  _StructureBandPainter({
    required this.segments,
    required this.durationSeconds,
  });

  final List<Segment> segments;
  final double durationSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    if (durationSeconds <= 0) {
      return;
    }

    for (final segment in segments) {
      if (segment.type == SegmentType.unknown) {
        continue;
      }

      final startX = (segment.startSeconds / durationSeconds) * size.width;
      final endX = (segment.endSeconds / durationSeconds) * size.width;
      final color = switch (segment.type) {
        SegmentType.prelude => AppColors.segmentPrelude,
        SegmentType.interlude => AppColors.segmentInterlude,
        SegmentType.postlude => AppColors.segmentPostlude,
        SegmentType.unknown => Colors.transparent,
      };

      final paint = Paint()..color = color.withValues(alpha: 0.22);
      canvas.drawRect(
        Rect.fromLTRB(startX, 0, endX, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StructureBandPainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.durationSeconds != durationSeconds;
  }
}

/// Visual-only waveform for Method 2 — no [PlayerController], no audio bleed.
class VisualWaveformWidget extends StatelessWidget {
  const VisualWaveformWidget({
    super.key,
    required this.waveformData,
    required this.durationSeconds,
    required this.position,
    required this.onSeek,
    required this.waveColor,
    this.height = 72,
    this.showPlayhead = true,
    this.showTimeMarkers = true,
  });

  final List<double> waveformData;
  final double durationSeconds;
  final Duration position;
  final ValueChanged<Duration> onSeek;
  final Color waveColor;
  final double height;
  final bool showPlayhead;
  final bool showTimeMarkers;

  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    if (durationSeconds <= 0) {
      return;
    }
    final ratio =
        (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    onSeek(
      Duration(
        milliseconds: (durationSeconds * 1000 * ratio).round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTimeMarkers && durationSeconds > 0) ...[
          _TimeMarkers(durationSeconds: durationSeconds),
          const SizedBox(height: 6),
        ],
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapUp: (details) => _handleTap(details, constraints),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.surfaceBorder),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BarWaveformPainter(
                          waveformData: waveformData,
                          waveColor: waveColor,
                        ),
                      ),
                    ),
                    if (showPlayhead && durationSeconds > 0)
                      Positioned(
                        left: constraints.maxWidth *
                            (position.inMilliseconds /
                                (durationSeconds * 1000)
                                    .clamp(1, double.infinity)),
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          color: AppColors.textPrimary.withValues(alpha: 0.9),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BarWaveformPainter extends CustomPainter {
  _BarWaveformPainter({
    required this.waveformData,
    required this.waveColor,
  });

  final List<double> waveformData;
  final Color waveColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) {
      return;
    }

    final count = waveformData.length;
    final slotWidth = size.width / count;
    final barWidth = (slotWidth * 0.55).clamp(1.5, 6.0);
    final paint = Paint()..color = waveColor.withValues(alpha: 0.55);

    for (var i = 0; i < count; i++) {
      final amplitude = waveformData[i].clamp(0.0, 1.0);
      final barHeight = math.max(2.0, amplitude * size.height * 0.88);
      final centerX = i * slotWidth + slotWidth / 2;
      final top = (size.height - barHeight) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(centerX - barWidth / 2, top, barWidth, barHeight),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarWaveformPainter oldDelegate) {
    return oldDelegate.waveformData != waveformData ||
        oldDelegate.waveColor != waveColor;
  }
}
