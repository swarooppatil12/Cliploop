import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/stem_utils.dart';
import '../../../models/track_stem.dart';
import '../../../providers/player_provider.dart';
import '../../../services/file_service.dart';
import 'waveform_widget.dart';

class StemPlayerCard extends StatefulWidget {
  const StemPlayerCard({
    super.key,
    required this.stem,
    required this.durationSeconds,
    required this.onDownload,
    this.animationIndex = 0,
  });

  final TrackStem stem;
  final double durationSeconds;
  final Future<void> Function() onDownload;
  final int animationIndex;

  @override
  State<StemPlayerCard> createState() => _StemPlayerCardState();
}

class _StemPlayerCardState extends State<StemPlayerCard> {
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 148,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(StemUtils.iconFor(stem.type), color: color, size: 20),
                      const SizedBox(width: 8),
                      Text(StemUtils.labelFor(stem.type), style: AppTextStyles.headlineMedium),
                      const Spacer(),
                      IconButton(
                        onPressed: _isDownloading
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                unawaited(_handleDownload());
                              },
                        icon: _isDownloading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_rounded),
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: MediaQuery.sizeOf(context).width - 80,
                      height: 56,
                      child: _showWaveformShimmer
                          ? Shimmer.fromColors(
                              baseColor: AppColors.surfaceBorder,
                              highlightColor: AppColors.surfaceElevated,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            )
                          : WaveformWidget(
                              waveformData: stem.waveformData,
                              audioPath: stem.audioPath,
                              durationSeconds: widget.durationSeconds,
                              position: player.currentPosition,
                              waveColor: color,
                              onSeek: player.seek,
                              height: 56,
                              showTimeMarkers: false,
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _showWaveformShimmer
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                unawaited(player.toggleStem(stem.id));
                              },
                        icon: Icon(
                          isPlayingStem ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        ),
                        color: color,
                      ),
                      IconButton(
                        onPressed: _showWaveformShimmer
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                player.toggleMute(stem.id);
                              },
                        icon: Icon(isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
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
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(
          duration: 450.ms,
          curve: Curves.easeOutCubic,
          delay: (widget.animationIndex * 100).ms,
        )
        .slideX(
          begin: 0.15,
          curve: Curves.easeOutCubic,
          delay: (widget.animationIndex * 100).ms,
        );
  }
}

Future<void> downloadStemFile({
  required TrackStem stem,
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
    await fileService.saveToDownloads(
      stem.audioPath,
      '${StemUtils.labelFor(stem.type).toLowerCase()}_${stem.id}.wav',
    );
    messenger.showSnackBar(
      SnackBar(content: Text('${StemUtils.labelFor(stem.type)} saved to downloads')),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Download failed: $error')),
    );
  }
}
