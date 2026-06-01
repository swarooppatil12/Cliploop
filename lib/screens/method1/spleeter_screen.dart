import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/layout_constants.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/segment_labels.dart';
import '../../core/utils/time_formatter.dart';
import '../../models/segment.dart';
import '../../models/separation_result.dart';
import '../../models/track_stem.dart';
import '../../services/file_service.dart';
import '../../services/gapless_mix_service.dart';
import '../../providers/music_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/spleeter_service.dart';
import '../../widgets/common/custom_app_bar.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/method_page_header.dart';
import '../method2/widgets/structure_timeline.dart';
import '../shared/widgets/song_player_controls.dart';
import '../shared/widgets/structure_detection_summary.dart';
import '../shared/widgets/gapless_mix_panel.dart';
import '../shared/widgets/structure_segment_list.dart';
import '../shared/widgets/vocal_detection_list.dart';
import 'widgets/waveform_widget.dart';

class SpleeterScreen extends StatefulWidget {
  const SpleeterScreen({super.key});

  @override
  State<SpleeterScreen> createState() => _SpleeterScreenState();
}

class _SpleeterScreenState extends State<SpleeterScreen> {
  List<double> _masterWaveform = const [];
  bool _loadingWaveform = false;
  Segment? _selectedSegment;
  MusicProvider? _musicProvider;
  String? _loadedFileId;
  bool _autoProcessingQueued = false;
  bool _buildingGapless = false;
  String? _gaplessWavPath;
  GaplessMixResult? _gaplessResult;
  final FileService _fileService = FileService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _musicProvider = context.read<MusicProvider>();
      if (_musicProvider!.selectedFile == null) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.home);
        }
        return;
      }
      _musicProvider!.addListener(_onMusicProviderChanged);
      _loadedFileId = _musicProvider!.selectedFile?.id;
      unawaited(_initialize());
      _maybeStartProcessing();
    });
  }

  @override
  void dispose() {
    _musicProvider?.removeListener(_onMusicProviderChanged);
    super.dispose();
  }

  void _onMusicProviderChanged() {
    final fileId = _musicProvider?.selectedFile?.id;
    if (fileId == _loadedFileId) {
      return;
    }

    _loadedFileId = fileId;
    if (!mounted) {
      return;
    }

    if (fileId == null) {
      Navigator.pushReplacementNamed(context, AppRoutes.home);
      return;
    }

    setState(() {
      _selectedSegment = null;
      _masterWaveform = const [];
      _gaplessWavPath = null;
      _gaplessResult = null;
    });
    unawaited(_initialize());
    _maybeStartProcessing();
  }

  void _maybeStartProcessing() {
    if (_autoProcessingQueued || !mounted || _musicProvider == null) {
      return;
    }

    if (_musicProvider!.selectedFile == null ||
        !_musicProvider!.consumeSpleeterNeedsRun()) {
      return;
    }

    _autoProcessingQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoProcessingQueued = false;
      if (!mounted) {
        return;
      }
      Navigator.pushNamed(context, AppRoutes.processing, arguments: 'spleeter');
    });
  }

  Future<void> _initialize() async {
    final musicProvider = context.read<MusicProvider>();
    final playerProvider = context.read<PlayerProvider>();
    final selectedFile = musicProvider.selectedFile;
    final result =
        musicProvider.hasValidSpleeterResult ? musicProvider.spleeterResult : null;

    playerProvider.reset();
    if (selectedFile != null && selectedFile.path.isNotEmpty) {
      playerProvider.loadStem(selectedFile.path, 'structure_master');
    }

    final structureSegments = _structureSegments(result?.structureSegments);
    final preferredSegment = preferredStructureSegment(structureSegments);
    if (preferredSegment != null) {
      setState(() => _selectedSegment = preferredSegment);
    } else {
      setState(() => _selectedSegment = null);
    }

    if (selectedFile == null) {
      return;
    }

    setState(() => _loadingWaveform = true);
    try {
      final waveform = await SpleeterService().generateWaveform(selectedFile.path);
      if (mounted) {
        setState(() {
          _masterWaveform = waveform;
          _loadingWaveform = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingWaveform = false);
      }
    }
  }

  List<Segment> _structureSegments(List<Segment>? segments) {
    if (segments == null) {
      return const [];
    }

    final markers = segments
        .where((segment) => segment.type != SegmentType.unknown)
        .toList()
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    return markers;
  }

  double _durationSeconds(MusicProvider musicProvider) {
    final file = musicProvider.selectedFile;
    if (file != null && file.durationSeconds > 0) {
      return file.durationSeconds.toDouble();
    }

    final segments = musicProvider.hasValidSpleeterResult
        ? musicProvider.spleeterResult?.structureSegments ?? const []
        : const [];
    if (segments.isEmpty) {
      return 0;
    }

    return segments
        .map((segment) => segment.endSeconds)
        .reduce((a, b) => a > b ? a : b);
  }

  void _skipSegment(int direction) {
    final musicProvider = context.read<MusicProvider>();
    if (!musicProvider.hasValidSpleeterResult) {
      return;
    }

    final segments =
        _structureSegments(musicProvider.spleeterResult?.structureSegments);
    if (segments.isEmpty) {
      return;
    }

    final currentIndex = _selectedSegment == null
        ? -1
        : segments.indexWhere((segment) => segment.id == _selectedSegment!.id);

    var nextIndex = currentIndex + direction;
    if (nextIndex < 0) {
      nextIndex = 0;
    } else if (nextIndex >= segments.length) {
      nextIndex = segments.length - 1;
    }

    _selectSegment(segments[nextIndex]);
  }

  String? _stemPath(SeparationResult result, StemType type) {
    for (final stem in result.stems) {
      if (stem.type == type && stem.audioPath.isNotEmpty) {
        return stem.audioPath;
      }
    }
    return null;
  }

  Future<void> _createGaplessMix() async {
    final musicProvider = context.read<MusicProvider>();
    final playerProvider = context.read<PlayerProvider>();
    final file = musicProvider.selectedFile;
    final result = musicProvider.spleeterResult;
    if (file == null || result == null || !musicProvider.hasValidSpleeterResult) {
      return;
    }

    setState(() => _buildingGapless = true);
    try {
      final export = await SpleeterService().exportGaplessMix(
        inputPath: file.path,
        structureSegments: _structureSegments(result.structureSegments),
        vocalsStemPath: _stemPath(result, StemType.vocals),
        drumsStemPath: _stemPath(result, StemType.accompaniment),
      );
      if (!mounted) return;
      setState(() {
        _gaplessWavPath = export.wavPath;
        _gaplessResult = export.result;
      });
      playerProvider.loadStem(export.wavPath, 'gapless_mix');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            export.result.interludeCount == 0
                ? 'Gapless mix ready (no interludes removed).'
                : 'Gapless mix ready — ${export.result.removedSeconds.toStringAsFixed(1)}s of interludes removed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gapless mix failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _buildingGapless = false);
    }
  }

  Future<void> _saveGaplessMix() async {
    final path = _gaplessWavPath;
    final file = context.read<MusicProvider>().selectedFile;
    if (path == null || file == null) return;

    try {
      final base = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      await _fileService.saveToDownloads(path, '${base}_gapless.wav');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gapless mix saved to downloads')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $error')),
      );
    }
  }

  void _playGaplessMix() {
    final path = _gaplessWavPath;
    if (path == null) return;
    final player = context.read<PlayerProvider>();
    player.playbackSegment = null;
    player.loadStem(path, 'gapless_mix');
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

  @override
  Widget build(BuildContext context) {
    final musicProvider = context.watch<MusicProvider>();
    final playerProvider = context.watch<PlayerProvider>();
    final selectedFile = musicProvider.selectedFile;
    final result =
        musicProvider.hasValidSpleeterResult ? musicProvider.spleeterResult : null;
    final durationSeconds = _durationSeconds(musicProvider);
    final structureSegments = _structureSegments(result?.structureSegments);
    final vocalOutput = result?.vocalModelOutput;
    final hasResults = result != null;
    final hasStructure = structureSegments.isNotEmpty;
    final isProcessing = musicProvider.spleeterState == ProcessingState.preparing ||
        musicProvider.spleeterState == ProcessingState.processing;

    if (selectedFile == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBar(
        showBackButton: true,
        title: 'Song Structure',
      ),
      body: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: AppLayout.pagePadding(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MethodPageHeader(
                          methodLabel: 'Method 1',
                          accentColor: AppColors.primaryGreen,
                          icon: Icons.auto_awesome_rounded,
                          title: 'Song Structure',
                          subtitle:
                              'Detect Prelude, Interlude, and Postlude sections using on-device ML and voice activity detection.',
                        ),
                        const SizedBox(height: 20),
                        _TrackInfoCard(
                          fileName: selectedFile.name,
                          durationSeconds: durationSeconds,
                        ),
                        const SizedBox(height: 20),
                        if (!hasResults)
                          isProcessing
                              ? _ProcessingCard(
                                  progress: musicProvider.spleeterProgress,
                                )
                              : _EmptyResultsCard(
                                  onAnalyse: () {
                                    musicProvider.markSpleeterNeedsRun();
                                    Navigator.pushNamed(
                                      context,
                                      AppRoutes.processing,
                                      arguments: 'spleeter',
                                    );
                                  },
                                )
                        else ...[
                          StructureDetectionSummary(segments: structureSegments),
                          const SizedBox(height: 20),
                          Text('Song overview', style: AppTextStyles.headlineLarge),
                          const SizedBox(height: 10),
                          if (_loadingWaveform)
                            Shimmer.fromColors(
                              baseColor: AppColors.surfaceBorder,
                              highlightColor: AppColors.surfaceElevated,
                              child: Container(
                                height: 96,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            )
                          else
                            WaveformWidget(
                              waveformData: _masterWaveform,
                              audioPath: selectedFile.path,
                              durationSeconds: durationSeconds,
                              position: playerProvider.currentPosition,
                              isMaster: true,
                              structureSegments: structureSegments,
                              onSeek: playerProvider.seek,
                            ),
                          if (durationSeconds > 0) ...[
                            const SizedBox(height: 20),
                            StructureTimeline(
                              durationSeconds: durationSeconds,
                              structureSegments: structureSegments,
                              position: playerProvider.currentPosition,
                              selectedSegmentId: _selectedSegment?.id,
                              onSegmentSelected: _selectSegment,
                              onSeek: playerProvider.seek,
                            ),
                          ],
                          const SizedBox(height: 24),
                          StructureSegmentList(
                            segments: structureSegments,
                            selectedSegmentId: _selectedSegment?.id,
                            onSegmentTap: _selectSegment,
                          ),
                          const SizedBox(height: 20),
                          GaplessMixPanel(
                            interludeCount:
                                structureInterludeCount(structureSegments),
                            isBuilding: _buildingGapless,
                            lastExport: _gaplessResult,
                            onCreate: _createGaplessMix,
                            onPlay: _gaplessWavPath != null ? _playGaplessMix : null,
                            onSave: _gaplessWavPath != null ? _saveGaplessMix : null,
                          ),
                          const SizedBox(height: 28),
                          if (vocalOutput != null) ...[
                            VocalDetectionList(
                              vocalOutput: vocalOutput,
                              onSegmentTap: (segment) =>
                                  _selectSegment(segment, autoPlay: false),
                            ),
                            if (vocalOutput.rawLog.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              RawModelOutputPanel(rawLog: vocalOutput.rawLog),
                            ],
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                if (hasResults && hasStructure)
                  SongPlayerControls(
                    durationSeconds: durationSeconds,
                    currentSegment: _selectedSegment,
                    structureSegments: structureSegments,
                    onPrevious: () => _skipSegment(-1),
                    onNext: () => _skipSegment(1),
                  ),
              ],
            ),
    );
  }
}

class _TrackInfoCard extends StatelessWidget {
  const _TrackInfoCard({
    required this.fileName,
    required this.durationSeconds,
  });

  final String fileName;
  final double durationSeconds;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppLayout.cardRadius),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.audiotrack_rounded,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: AppTextStyles.headlineMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (durationSeconds > 0)
                  Text(
                    TimeFormatter.formatDuration(durationSeconds.round()),
                    style: AppTextStyles.mono.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResultsCard extends StatelessWidget {
  const _EmptyResultsCard({required this.onAnalyse});

  final VoidCallback onAnalyse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Analyse this song', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'We will find the Prelude, Interlude, and Postlude sections in your song.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: 'Detect structure',
            icon: Icons.auto_awesome_rounded,
            onPressed: onAnalyse,
          ),
        ],
      ),
    );
  }
}

class _ProcessingCard extends StatelessWidget {
  const _ProcessingCard({required this.progress});

  final int progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Analysing song…',
            style: AppTextStyles.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Finding Prelude, Interlude, and Postlude — $progress%',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
