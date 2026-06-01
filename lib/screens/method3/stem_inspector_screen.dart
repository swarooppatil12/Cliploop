import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/layout_constants.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/segment_labels.dart';
import '../../core/utils/time_formatter.dart';
import '../../models/segment.dart';
import '../../models/stem_pair_result.dart';
import '../../providers/player_provider.dart';
import '../../providers/stem_pair_provider.dart';
import '../../services/gapless_mix_service.dart';
import '../../services/stem_pair_service.dart';
import '../../widgets/common/bottom_nav_bar.dart';
import '../../widgets/common/custom_app_bar.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/method_page_header.dart';
import '../method1/widgets/waveform_widget.dart';
import '../method2/widgets/structure_timeline.dart';
import '../shared/widgets/gapless_mix_panel.dart';
import '../shared/widgets/song_player_controls.dart';
import '../shared/widgets/structure_detection_summary.dart';
import '../shared/widgets/structure_segment_list.dart';
import '../shared/widgets/vocal_detection_list.dart';
import 'widgets/stem_upload_card.dart';
import 'widgets/structure_legend.dart';
import 'widgets/vocal_silence_panel.dart';

class StemInspectorScreen extends StatefulWidget {
  const StemInspectorScreen({super.key});

  @override
  State<StemInspectorScreen> createState() => _StemInspectorScreenState();
}

class _StemInspectorScreenState extends State<StemInspectorScreen> {
  static const _navIndex = 2;

  Segment? _selectedSegment;
  bool _buildingGapless = false;
  String? _gaplessWavPath;
  GaplessMixResult? _gaplessResult;
  final StemPairService _stemPairService = StemPairService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBar(
        isRootTab: true,
        title: 'Stem Inspector',
      ),
      body: Consumer2<StemPairProvider, PlayerProvider>(
        builder: (context, stemProvider, player, _) {
          final result = stemProvider.result;
          final isAnalyzing = stemProvider.state == StemPairState.analyzing;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: AppLayout.pagePadding(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MethodPageHeader(
                        methodLabel: 'Method 3',
                        accentColor: AppColors.accentOrange,
                        icon: Icons.upload_file_rounded,
                        title: 'Stem Inspector',
                        subtitle:
                            'Upload pre-separated vocal and instrumental stems. Analysis only — detects Prelude, Interlude, and Postlude.',
                      ),
                      const SizedBox(height: 16),
                      const StructureLegend(),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StemUploadCard(
                            title: 'Vocal stem',
                            subtitle:
                                'Pre-separated vocal file — MP3, WAV, M4A…',
                            fileName: stemProvider.vocalFileName,
                            borderColor: AppColors.stemVocals,
                            icon: Icons.mic_rounded,
                            onTap: isAnalyzing
                                ? () {}
                                : () => unawaited(stemProvider.pickVocal()),
                          ),
                          const SizedBox(width: 12),
                          StemUploadCard(
                            title: 'Instrumental stem',
                            subtitle:
                                'Pre-separated background music file',
                            fileName: stemProvider.bgmFileName,
                            borderColor: AppColors.stemAccompaniment,
                            icon: Icons.piano_rounded,
                            onTap: isAnalyzing
                                ? () {}
                                : () => unawaited(stemProvider.pickBgm()),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: GradientButton(
                              label: isAnalyzing
                                  ? 'Analyzing…'
                                  : 'Analyze stems',
                              onPressed: stemProvider.canAnalyze
                                  ? () => unawaited(stemProvider.analyze())
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _StatusLine(stemProvider: stemProvider),
                      if (result != null) ...[
                        const SizedBox(height: 24),
                        _MetaRow(result: result),
                        if (result.warnings.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            result.warnings.join(' '),
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.accentOrange,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _StemWaveCard(
                                label: 'Vocal track',
                                color: AppColors.stemVocals,
                                audioPath: result.vocalStemPath,
                                waveform: result.vocalWaveform,
                                durationSeconds: result.durationSeconds,
                                silenceRegions: result.vocalSilence.regions,
                                player: player,
                                onPlay: () => _playStem(
                                  player,
                                  result.vocalStemPath,
                                  'vocal_m3',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StemWaveCard(
                                label: 'Instrumental track',
                                color: AppColors.stemAccompaniment,
                                audioPath: result.bgmStemPath,
                                waveform: result.bgmWaveform,
                                durationSeconds: result.durationSeconds,
                                player: player,
                                onPlay: () => _playStem(
                                  player,
                                  result.bgmStemPath,
                                  'bgm_m3',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        VocalSilencePanel(
                          summary: result.vocalSilence,
                          durationSeconds: result.durationSeconds,
                        ),
                        const SizedBox(height: 20),
                        StructureDetectionSummary(
                          segments: result.structureSegments,
                        ),
                        const SizedBox(height: 20),
                        Text('Structure detection', style: AppTextStyles.headlineLarge),
                        const SizedBox(height: 10),
                        StructureTimeline(
                          durationSeconds: result.durationSeconds,
                          structureSegments: result.structureSegments,
                          position: player.currentPosition,
                          selectedSegmentId: _selectedSegment?.id,
                          onSegmentSelected: _selectSegment,
                          onSeek: player.seek,
                        ),
                        const SizedBox(height: 20),
                        StructureSegmentList(
                          segments: result.structureSegments,
                          selectedSegmentId: _selectedSegment?.id,
                          onSegmentTap: _selectSegment,
                        ),
                        const SizedBox(height: 20),
                        GaplessMixPanel(
                          interludeCount: structureInterludeCount(
                            result.structureSegments,
                          ),
                          isBuilding: _buildingGapless,
                          lastExport: _gaplessResult,
                          onCreate: () => _createGaplessMix(result),
                          onPlay: _gaplessWavPath != null ? _playGaplessMix : null,
                          onSave: null,
                        ),
                        const SizedBox(height: 24),
                        VocalDetectionList(
                          vocalOutput: result.vocalModelOutput,
                          onSegmentTap: (segment) =>
                              _selectSegment(segment, autoPlay: false),
                        ),
                        const SizedBox(height: 20),
                        RawModelOutputPanel(
                          rawLog: result.vocalModelOutput.rawLog,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (result != null && result.structureSegments.isNotEmpty)
                SongPlayerControls(
                  durationSeconds: result.durationSeconds,
                  currentSegment: _selectedSegment,
                  structureSegments: result.structureSegments,
                  onPrevious: () => _skipSegment(result.structureSegments, -1),
                  onNext: () => _skipSegment(result.structureSegments, 1),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _navIndex,
        onTap: (index) => AppRoutes.onBottomNavTap(context, index),
      ),
    );
  }

  void _playStem(PlayerProvider player, String path, String id) {
    player.playbackSegment = null;
    player.loadStem(path, id);
    player.playAll();
  }

  void _selectSegment(Segment segment, {bool autoPlay = true}) {
    setState(() => _selectedSegment = segment);
    final player = context.read<PlayerProvider>();
    if (autoPlay) {
      player.playStructureSegment(segment);
    } else {
      player.seek(
        Duration(milliseconds: (segment.startSeconds * 1000).round()),
      );
    }
  }

  void _skipSegment(List<Segment> segments, int delta) {
    if (segments.isEmpty) {
      return;
    }
    final current = _selectedSegment;
    var index = current == null
        ? 0
        : segments.indexWhere((s) => s.id == current.id);
    if (index < 0) {
      index = 0;
    }
    index += delta;
    if (index < 0) {
      index = 0;
    } else if (index >= segments.length) {
      index = segments.length - 1;
    }
    _selectSegment(segments[index]);
  }

  Future<void> _createGaplessMix(StemPairResult result) async {
    setState(() => _buildingGapless = true);
    try {
      final export = await _stemPairService.exportGaplessMix(
        vocalStemPath: result.vocalStemPath,
        bgmStemPath: result.bgmStemPath,
        structureSegments: result.structureSegments,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _gaplessWavPath = export.wavPath;
        _gaplessResult = export.result;
      });
      context.read<PlayerProvider>().loadStem(export.wavPath, 'gapless_m3');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            export.result.interludeCount == 0
                ? 'Gapless mix ready (no interludes removed).'
                : 'Gapless mix ready — ${export.result.removedSeconds.toStringAsFixed(1)}s removed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gapless mix failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _buildingGapless = false);
      }
    }
  }

  void _playGaplessMix() {
    final path = _gaplessWavPath;
    if (path == null) {
      return;
    }
    final player = context.read<PlayerProvider>();
    player.playbackSegment = null;
    player.loadStem(path, 'gapless_m3');
    player.playAll();
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.stemProvider});

  final StemPairProvider stemProvider;

  @override
  Widget build(BuildContext context) {
    String text;
    Color color = AppColors.textSecondary;

    switch (stemProvider.state) {
      case StemPairState.analyzing:
        text = 'Analyzing vocal + instrumental stems…';
        color = AppColors.primaryPurple;
      case StemPairState.error:
        text = stemProvider.errorMessage ?? 'Analysis failed.';
        color = AppColors.accentPink;
      case StemPairState.complete:
        final s = stemProvider.result!.vocalSilence;
        text =
            'Done — ${s.regionCount} vocal silence region(s) ≥ 10s (${s.percentQuiet}% of song quiet on vocal stem).';
        color = AppColors.primaryGreen;
      case StemPairState.idle:
        if (stemProvider.vocalPath != null && stemProvider.bgmPath != null) {
          text = 'Both stems loaded. Tap Analyze stems.';
        } else if (stemProvider.vocalPath != null) {
          text = 'Vocal loaded. Upload the instrumental stem (right).';
        } else if (stemProvider.bgmPath != null) {
          text = 'Instrumental loaded. Upload the vocal stem (left).';
        } else {
          text = 'Upload vocal and instrumental files to begin.';
        }
    }

    return Text(text, style: AppTextStyles.bodyMedium.copyWith(color: color));
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.result});

  final StemPairResult result;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        Text('Vocal: ${result.vocalFileName}', style: AppTextStyles.labelSmall),
        Text('BGM: ${result.bgmFileName}', style: AppTextStyles.labelSmall),
        Text(
          TimeFormatter.formatPrecise(result.durationSeconds),
          style: AppTextStyles.labelSmall,
        ),
        Text('${result.sampleRate} Hz', style: AppTextStyles.labelSmall),
      ],
    );
  }
}

class _StemWaveCard extends StatelessWidget {
  const _StemWaveCard({
    required this.label,
    required this.color,
    required this.audioPath,
    required this.waveform,
    required this.durationSeconds,
    required this.player,
    required this.onPlay,
    this.silenceRegions,
  });

  final String label;
  final Color color;
  final String audioPath;
  final List<double> waveform;
  final double durationSeconds;
  final PlayerProvider player;
  final VoidCallback onPlay;
  final List<dynamic>? silenceRegions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: AppTextStyles.headlineMedium),
              const Spacer(),
              TextButton(onPressed: onPlay, child: const Text('Play')),
            ],
          ),
          WaveformWidget(
            waveformData: waveform,
            audioPath: audioPath,
            durationSeconds: durationSeconds,
            position: player.currentPosition,
            waveColor: color,
            onSeek: player.seek,
            height: 72,
            showTimeMarkers: false,
          ),
        ],
      ),
    );
  }
}
