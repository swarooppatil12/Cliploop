import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/segment_labels.dart';
import '../../../models/segment.dart';
import '../../../providers/player_provider.dart';
import '../../../widgets/common/audio_seek_bar.dart';

class SongPlayerControls extends StatelessWidget {
  const SongPlayerControls({
    super.key,
    required this.durationSeconds,
    this.currentSegment,
    this.structureSegments = const [],
    this.onPrevious,
    this.onNext,
  });

  final double durationSeconds;
  final Segment? currentSegment;
  final List<Segment> structureSegments;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  Color _colorFor(Segment? segment) {
    if (segment == null) {
      return AppColors.primaryGreen;
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
      return 'Full song';
    }
    return structureSegmentDisplayName(segment, structureSegments);
  }

  Duration _segmentRelativePosition(PlayerProvider player, Segment segment) {
    final startMs = (segment.startSeconds * 1000).round();
    final endMs = (segment.endSeconds * 1000).round();
    final relMs = player.currentPosition.inMilliseconds - startMs;
    return Duration(
      milliseconds: relMs.clamp(0, math.max(0, endMs - startMs)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final activeSegment = currentSegment ?? player.playbackSegment;
    final fullDuration =
        Duration(milliseconds: (durationSeconds * 1000).round());
    final color = _colorFor(activeSegment);
    final hasNavigation = onPrevious != null && onNext != null;

    final Duration seekDuration;
    final Duration seekPosition;
    if (activeSegment != null) {
      final startMs = (activeSegment.startSeconds * 1000).round();
      final endMs = (activeSegment.endSeconds * 1000).round();
      seekDuration = Duration(milliseconds: math.max(1, endMs - startMs));
      seekPosition = _segmentRelativePosition(player, activeSegment);
    } else {
      seekDuration = fullDuration;
      seekPosition = player.currentPosition;
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _labelFor(activeSegment),
                style: AppTextStyles.headlineMedium.copyWith(color: color),
              ),
              const SizedBox(height: 10),
              AudioSeekBar(
                position: seekPosition,
                duration: seekDuration,
                onChanged: (value) {
                  if (activeSegment != null) {
                    final segmentDurationMs = seekDuration.inMilliseconds;
                    final startMs =
                        (activeSegment.startSeconds * 1000).round();
                    player.seek(
                      Duration(
                        milliseconds:
                            startMs + (segmentDurationMs * value).round(),
                      ),
                    );
                  } else {
                    player.seek(
                      Duration(
                        milliseconds:
                            (fullDuration.inMilliseconds * value).round(),
                      ),
                    );
                  }
                },
                onChangeEnd: (_) {},
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasNavigation)
                    IconButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        onPrevious!();
                      },
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                  IconButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      player.togglePlayPause(segment: activeSegment);
                    },
                    icon: Icon(
                      player.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                    ),
                    iconSize: 48,
                    color: color,
                  ),
                  if (hasNavigation)
                    IconButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        onNext!();
                      },
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
