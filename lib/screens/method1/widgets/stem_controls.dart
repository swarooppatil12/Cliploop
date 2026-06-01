import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/player_provider.dart';
import '../../../widgets/common/audio_seek_bar.dart';

class StemControls extends StatelessWidget {
  const StemControls({
    super.key,
    required this.durationSeconds,
  });

  final double durationSeconds;

  static const _speeds = [0.5, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final duration = Duration(
      milliseconds: (durationSeconds * 1000).round(),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AudioSeekBar(
            position: player.currentPosition,
            duration: duration,
            onChanged: (value) {
              player.seek(
                Duration(milliseconds: (duration.inMilliseconds * value).round()),
              );
            },
            onChangeEnd: (_) {},
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  player.togglePlayPause();
                },
                icon: Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                label: Text(player.isPlaying ? 'Pause All' : 'Play All'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Solo'),
                selected: player.soloModeEnabled,
                onSelected: (_) => player.toggleSoloMode(),
                selectedColor: AppColors.primaryGreen.withValues(alpha: 0.25),
                checkmarkColor: AppColors.primaryGreen,
              ),
              const Spacer(),
              PopupMenuButton<double>(
                initialValue: player.playbackSpeed,
                onSelected: player.setPlaybackSpeed,
                itemBuilder: (context) {
                  return _speeds
                      .map(
                        (speed) => PopupMenuItem<double>(
                          value: speed,
                          child: Text('${speed}x'),
                        ),
                      )
                      .toList();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Text(
                    '${player.playbackSpeed}x',
                    style: AppTextStyles.bodyLarge,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
