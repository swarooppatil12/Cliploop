import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/stem_utils.dart';
import '../../../core/utils/time_formatter.dart';
import '../../../models/track_stem.dart';
import '../../../providers/player_provider.dart';
import '../../../services/file_service.dart';
import '../../method1/widgets/waveform_widget.dart';

class VocalRemoverStemCard extends StatefulWidget {
  const VocalRemoverStemCard({
    super.key,
    required this.stem,
    required this.title,
    required this.subtitle,
    required this.durationSeconds,
    required this.onDownload,
    this.animationIndex = 0,
  });

  final TrackStem stem;
  final String title;
  final String subtitle;
  final double durationSeconds;
  final Future<void> Function() onDownload;
  final int animationIndex;

  @override
  State<VocalRemoverStemCard> createState() => _VocalRemoverStemCardState();
}

class _VocalRemoverStemCardState extends State<VocalRemoverStemCard> {
  bool _isDownloading = false;

  bool get _showWaveformShimmer =>
      _isDownloading || widget.stem.audioPath.isEmpty;

  Future<void> _handleDownload() async {
    setState(() => _isDownloading = true);
    try {
      await widget.onDownload();
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final stem = widget.stem;
    final color = StemUtils.colorFor(stem.type);
    final isMuted = player.stemMuteState[stem.id] ?? stem.isMuted;
    final volume = player.stemVolumeState[stem.id] ?? stem.volume;
    final isPlayingStem = player.activeStemId == stem.id && player.isPlaying;
    final isActiveStem =
        player.activeStemId == null || player.activeStemId == stem.id;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.14),
            AppColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(StemUtils.iconFor(stem.type), color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: AppTextStyles.headlineLarge),
                      Text(
                        widget.subtitle,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isDownloading
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          unawaited(_handleDownload());
                        },
                  icon: _isDownloading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  color: AppColors.textSecondary,
                  tooltip: 'Download WAV',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_showWaveformShimmer)
              SizedBox(
                height: 72,
                child: Shimmer.fromColors(
                  baseColor: AppColors.surfaceBorder,
                  highlightColor: AppColors.surfaceElevated,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              )
            else
              VisualWaveformWidget(
                waveformData: stem.waveformData,
                durationSeconds: widget.durationSeconds,
                position: isActiveStem
                    ? player.currentPosition
                    : Duration.zero,
                waveColor: color,
                onSeek: player.seek,
                height: 56,
                showPlayhead: isActiveStem,
              ),
            if (isActiveStem && widget.durationSeconds > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    TimeFormatter.formatDuration(
                      player.currentPosition.inSeconds,
                    ),
                    style: AppTextStyles.mono.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    TimeFormatter.formatDuration(
                      widget.durationSeconds.round(),
                    ),
                    style: AppTextStyles.mono.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _showWaveformShimmer
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          if (!player.isStemReady(stem.id)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${widget.title} is still loading — '
                                  'try Separate again if this persists.',
                                ),
                              ),
                            );
                            return;
                          }
                          unawaited(player.toggleStem(stem.id));
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: Icon(
                    isPlayingStem ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(isPlayingStem ? 'Pause' : 'Play'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _showWaveformShimmer
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          player.toggleMute(stem.id);
                        },
                  icon: Icon(
                    isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  ),
                  color: AppColors.textSecondary,
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: color,
                      inactiveTrackColor: AppColors.surfaceBorder,
                      thumbColor: color,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: volume,
                      onChanged: _showWaveformShimmer
                          ? null
                          : (value) => player.setVolume(stem.id, value),
                    ),
                  ),
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
          delay: (widget.animationIndex * 120).ms,
        )
        .slideY(
          begin: 0.08,
          curve: Curves.easeOutCubic,
          delay: (widget.animationIndex * 120).ms,
        );
  }
}

Future<void> downloadVocalRemoverStem({
  required TrackStem stem,
  required String fileName,
  required FileService fileService,
  required ScaffoldMessengerState messenger,
}) async {
  if (stem.audioPath.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Stem file is not available locally yet')),
    );
    return;
  }

  try {
    await fileService.saveToDownloads(stem.audioPath, fileName);
    messenger.showSnackBar(
      SnackBar(content: Text('$fileName saved to downloads')),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Download failed: $error')),
    );
  }
}
