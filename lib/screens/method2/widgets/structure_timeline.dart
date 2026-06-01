import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/segment_labels.dart';
import '../../../core/utils/time_formatter.dart';
import '../../../models/segment.dart';

class TimelineBlock {
  const TimelineBlock({
    required this.startSeconds,
    required this.endSeconds,
    required this.type,
    this.segment,
  });

  final double startSeconds;
  final double endSeconds;
  final SegmentType type;
  final Segment? segment;

  double get durationSeconds => endSeconds - startSeconds;
}

List<TimelineBlock> buildTimelineBlocks({
  required List<Segment> structureSegments,
  required double totalDurationSeconds,
}) {
  if (totalDurationSeconds <= 0) {
    return const [];
  }

  final markers = structureSegments
      .where((segment) => segment.type != SegmentType.unknown)
      .toList()
    ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

  if (markers.isEmpty) {
    return [
      TimelineBlock(
        startSeconds: 0,
        endSeconds: totalDurationSeconds,
        type: SegmentType.unknown,
      ),
    ];
  }

  final blocks = <TimelineBlock>[];
  var cursor = 0.0;

  for (final segment in markers) {
    if (segment.startSeconds > cursor) {
      blocks.add(
        TimelineBlock(
          startSeconds: cursor,
          endSeconds: segment.startSeconds,
          type: SegmentType.unknown,
        ),
      );
    }

    blocks.add(
      TimelineBlock(
        startSeconds: segment.startSeconds,
        endSeconds: segment.endSeconds,
        type: segment.type,
        segment: segment,
      ),
    );
    cursor = segment.endSeconds;
  }

  if (cursor < totalDurationSeconds) {
    blocks.add(
      TimelineBlock(
        startSeconds: cursor,
        endSeconds: totalDurationSeconds,
        type: SegmentType.unknown,
      ),
    );
  }

  return blocks;
}

class StructureTimeline extends StatefulWidget {
  const StructureTimeline({
    super.key,
    required this.durationSeconds,
    required this.structureSegments,
    required this.position,
    required this.selectedSegmentId,
    required this.onSegmentSelected,
    required this.onSeek,
  });

  final double durationSeconds;
  final List<Segment> structureSegments;
  final Duration position;
  final String? selectedSegmentId;
  final ValueChanged<Segment> onSegmentSelected;
  final ValueChanged<Duration> onSeek;

  @override
  State<StructureTimeline> createState() => _StructureTimelineState();
}

class _StructureTimelineState extends State<StructureTimeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  double _pixelsPerSecond = 28;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _colorForType(SegmentType type) {
    return switch (type) {
      SegmentType.prelude => AppColors.segmentPrelude,
      SegmentType.interlude => AppColors.segmentInterlude,
      SegmentType.postlude => AppColors.segmentPostlude,
      SegmentType.unknown => AppColors.surfaceBorder,
    };
  }

  String _labelForType(SegmentType type) {
    return switch (type) {
      SegmentType.prelude => 'Prelude',
      SegmentType.interlude => 'Interlude',
      SegmentType.postlude => 'Postlude',
      SegmentType.unknown => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final blocks = buildTimelineBlocks(
      structureSegments: widget.structureSegments,
      totalDurationSeconds: widget.durationSeconds,
    );
    final timelineWidth = widget.durationSeconds * _pixelsPerSecond;
    final playheadX =
        widget.position.inMilliseconds / 1000 * _pixelsPerSecond;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Timeline', style: AppTextStyles.headlineLarge),
        const SizedBox(height: 10),
        Column(
          children: [
            GestureDetector(
              onScaleUpdate: (details) {
                setState(() {
                  _pixelsPerSecond =
                      (_pixelsPerSecond * details.scale).clamp(12.0, 72.0);
                });
              },
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(
                    timelineWidth,
                    MediaQuery.sizeOf(context).width - 40,
                  ),
                  height: 96,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Row(
                        children: blocks.map((block) {
                          final width = block.durationSeconds * _pixelsPerSecond;
                          final segment = block.segment;
                          final isSelected = segment != null &&
                              segment.id == widget.selectedSegmentId;
                          final isActive =
                              widget.position.inMilliseconds / 1000 >=
                                      block.startSeconds &&
                                  widget.position.inMilliseconds / 1000 <=
                                      block.endSeconds;

                          return AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              final pulse =
                                  isActive ? _pulseController.value : 0.0;
                              final color = _colorForType(block.type);
                              return GestureDetector(
                                onTap: segment == null
                                    ? null
                                    : () {
                                        HapticFeedback.mediumImpact();
                                        widget.onSegmentSelected(segment);
                                        widget.onSeek(
                                          Duration(
                                            milliseconds: (segment.startSeconds *
                                                    1000)
                                                .round(),
                                          ),
                                        );
                                      },
                                child: Container(
                                  width: width.clamp(24, double.infinity),
                                  decoration: BoxDecoration(
                                    color: color.withValues(
                                      alpha: block.type == SegmentType.unknown
                                          ? 0.55
                                          : 0.75 + pulse * 0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.textPrimary
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    block.segment == null
                                        ? _labelForType(block.type)
                                        : structureSegmentShortName(
                                            block.segment!,
                                            widget.structureSegments,
                                          ),
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: block.type == SegmentType.unknown
                                          ? AppColors.textDisabled
                                          : AppColors.background,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            },
                          );
                        }).toList(),
                      ),
                      Positioned(
                        left: playheadX.clamp(0, timelineWidth),
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: timelineWidth.clamp(
                  MediaQuery.sizeOf(context).width - 40,
                  double.infinity,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('0:00', style: AppTextStyles.labelSmall),
                    if (widget.durationSeconds > 60)
                      Text(
                        TimeFormatter.formatDuration(
                          (widget.durationSeconds / 2).round(),
                        ),
                        style: AppTextStyles.labelSmall,
                      ),
                    Text(
                      TimeFormatter.formatDuration(
                        widget.durationSeconds.round(),
                      ),
                      style: AppTextStyles.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        )
            .animate()
            .fadeIn(duration: 600.ms, curve: Curves.easeOutCubic)
            .slideX(
              begin: -0.25,
              duration: 600.ms,
              curve: Curves.easeOutCubic,
            ),
      ],
    );
  }
}
