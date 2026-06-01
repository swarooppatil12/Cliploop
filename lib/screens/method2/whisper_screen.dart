import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/processing_constants.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/layout_constants.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/segment_labels.dart';
import '../../core/utils/time_formatter.dart';
import '../../models/segment.dart';
import '../../models/track_stem.dart';
import '../../models/vocal_model_output.dart';
import '../../models/whisper_result.dart';
import '../../core/utils/processing_status_text.dart';
import '../../providers/music_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/file_service.dart';
import '../../services/gapless_mix_service.dart';
import '../../services/whisper_service.dart';
import '../../widgets/common/bottom_nav_bar.dart';
import '../../widgets/common/custom_app_bar.dart';
import '../../widgets/common/gradient_button.dart';
import '../../widgets/common/method_page_header.dart';
import '../shared/widgets/gapless_mix_panel.dart';
import '../shared/widgets/progress_indicator_widget.dart';
import '../shared/widgets/structure_detection_summary.dart';
import '../shared/widgets/structure_segment_list.dart';
import '../shared/widgets/vocal_detection_list.dart';
import 'widgets/structure_timeline.dart';
import 'widgets/vocal_remover_stem_card.dart';

String _method2SeparationEngineLabel() {
  return ProcessingConstants.mobileSeparationModelLabel;
}

class WhisperScreen extends StatefulWidget {
  const WhisperScreen({super.key});

  @override
  State<WhisperScreen> createState() => _WhisperScreenState();
}

class _WhisperScreenState extends State<WhisperScreen> {
  MusicProvider? _musicProvider;
  String? _loadedFileId;
  String? _playerSessionKey;
  ProcessingState? _lastWhisperState;
  bool _autoProcessingQueued = false;
  bool _structureExpanded = false;
  bool _buildingGapless = false;
  String? _gaplessWavPath;
  GaplessMixResult? _gaplessResult;
  Segment? _selectedSegment;
  final FileService _fileService = FileService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _musicProvider = context.read<MusicProvider>();
      _musicProvider!.addListener(_onMusicProviderChanged);
      _loadedFileId = _musicProvider!.selectedFile?.id;
      final willAutoSeparate = _musicProvider!.selectedFile != null &&
          _musicProvider!.whisperNeedsRun;
      _maybeStartProcessing();
      if (!willAutoSeparate && !_musicProvider!.isWhisperProcessing) {
        unawaited(_initializePlayer());
      }
    });
  }

  @override
  void dispose() {
    _musicProvider?.removeListener(_onMusicProviderChanged);
    super.dispose();
  }

  void _onMusicProviderChanged() {
    if (!mounted || _musicProvider == null) {
      return;
    }

    final fileId = _musicProvider!.selectedFile?.id;
    final whisperState = _musicProvider!.whisperState;
    final fileChanged = fileId != _loadedFileId;
    final whisperJustCompleted =
        whisperState == ProcessingState.complete &&
        _lastWhisperState != ProcessingState.complete;

    if (fileChanged) {
      _loadedFileId = fileId;
      _playerSessionKey = null;
      setState(() {
        _gaplessWavPath = null;
        _gaplessResult = null;
        _structureExpanded = false;
        _selectedSegment = null;
      });
    }

    _lastWhisperState = whisperState;

    if (_musicProvider!.isWhisperProcessing) {
      _maybeStartProcessing();
      return;
    }

    if (fileChanged || whisperJustCompleted || whisperState == ProcessingState.complete) {
      unawaited(_initializePlayer());
    }

    _maybeStartProcessing();
  }

  Future<void> _initializePlayer() async {
    final musicProvider = context.read<MusicProvider>();
    if (musicProvider.isWhisperProcessing) {
      if (kDebugMode) {
        debugPrint('[WhisperPlayer] defer preview — separation in progress');
      }
      return;
    }
    final playerProvider = context.read<PlayerProvider>();
    final result =
        musicProvider.hasValidWhisperResult ? musicProvider.whisperResult : null;

    final sessionKey = result != null
        ? 'stems:${result.musicFileId}:${result.processedAt.millisecondsSinceEpoch}'
        : 'preview:${musicProvider.selectedFile?.id ?? 'none'}';

    if (sessionKey == _playerSessionKey) {
      return;
    }

    if (kDebugMode) {
      debugPrint('[WhisperPlayer] rebind session=$sessionKey');
    }

    await playerProvider.resetAsync();
    _playerSessionKey = sessionKey;

    if (result != null && result.stems.isNotEmpty) {
      var loadedCount = 0;
      for (final stem in result.stems) {
        final path = stem.audioPath;
        if (path.isEmpty) {
          if (kDebugMode) {
            debugPrint('[WhisperPlayer] skip ${stem.id} — empty path');
          }
          continue;
        }
        if (!await File(path).exists()) {
          if (kDebugMode) {
            debugPrint('[WhisperPlayer] skip ${stem.id} — file missing: $path');
          }
          continue;
        }
        if (kDebugMode) {
          debugPrint('[WhisperPlayer] load ${stem.id} ← $path');
        }
        await playerProvider.loadStemAsync(path, stem.id);
        loadedCount++;
      }

      if (kDebugMode) {
        debugPrint('[WhisperPlayer] loaded $loadedCount stem(s) for playback');
      }
      return;
    }

    final selectedFile = musicProvider.selectedFile;
    if (selectedFile != null && selectedFile.path.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[WhisperPlayer] preview original (no stems yet): ${selectedFile.path}',
        );
      }
      await playerProvider.loadStemAsync(selectedFile.path, 'original');
    }
  }

  void _maybeStartProcessing() {
    if (_autoProcessingQueued || !mounted || _musicProvider == null) {
      return;
    }

    if (_musicProvider!.selectedFile == null || !_musicProvider!.whisperNeedsRun) {
      return;
    }

    _autoProcessingQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoProcessingQueued = false;
      if (!mounted || _musicProvider == null) {
        return;
      }
      unawaited(_beginSeparation(openFullScreen: false));
    });
  }

  void _openProcessingView() {
    Navigator.pushNamed(context, AppRoutes.processing, arguments: 'whisper');
  }

  Future<void> _pickFile() async {
    final provider = context.read<MusicProvider>();
    if (provider.isProcessing) {
      return;
    }
    await provider.pickAndLoadFile();
  }

  void _startSeparation() {
    final provider = context.read<MusicProvider>();
    if (provider.selectedFile == null || provider.isProcessing) {
      return;
    }
    _playerSessionKey = null;
    provider.markWhisperNeedsRun();
    unawaited(_beginSeparation(openFullScreen: true));
  }

  Future<void> _beginSeparation({required bool openFullScreen}) async {
    final provider = context.read<MusicProvider>();
    if (!provider.consumeWhisperNeedsRun()) {
      return;
    }

    await context.read<PlayerProvider>().resetAsync();
    _playerSessionKey = null;

    unawaited(provider.ensureProcessing(ActiveProcessingMethod.whisper));
    if (openFullScreen && mounted) {
      _openProcessingView();
    }
  }

  List<Segment> _structureSegments(WhisperResult? result) {
    if (result == null) {
      return const [];
    }

    final segments = result.segments
        .where((segment) => segment.type != SegmentType.unknown)
        .toList();
    segments.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    return segments;
  }

  double _durationSeconds(MusicProvider musicProvider) {
    final file = musicProvider.selectedFile;
    if (file != null && file.durationSeconds > 0) {
      return file.durationSeconds.toDouble();
    }

    final result = musicProvider.hasValidWhisperResult
        ? musicProvider.whisperResult
        : null;
    if (result == null) {
      return 0;
    }

    for (final stem in result.stems) {
      if (stem.durationSeconds > 0) {
        return stem.durationSeconds;
      }
    }

    final segments = _structureSegments(result);
    if (segments.isEmpty) {
      return 0;
    }

    return segments
        .map((segment) => segment.endSeconds)
        .reduce((a, b) => a > b ? a : b);
  }

  TrackStem? _stemFor(WhisperResult result, StemType type) {
    for (final stem in result.stems) {
      if (stem.type == type) {
        return stem;
      }
    }
    return null;
  }

  String? _stemPath(WhisperResult result, StemType type) {
    return _stemFor(result, type)?.audioPath;
  }

  String _downloadName(MusicProvider musicProvider, String suffix) {
    final base = musicProvider.selectedFile?.name.replaceAll(RegExp(r'\.[^.]+$'), '') ??
        'track';
    return '${base}_$suffix.wav';
  }

  Future<void> _createGaplessMix() async {
    final musicProvider = context.read<MusicProvider>();
    final playerProvider = context.read<PlayerProvider>();
    final file = musicProvider.selectedFile;
    final result = musicProvider.whisperResult;
    if (file == null || result == null || !musicProvider.hasValidWhisperResult) {
      return;
    }

    setState(() => _buildingGapless = true);
    try {
      final export = await WhisperService().exportGaplessMix(
        inputPath: file.path,
        structureSegments: _structureSegments(result),
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
        musicProvider.hasValidWhisperResult ? musicProvider.whisperResult : null;
    final durationSeconds = _durationSeconds(musicProvider);
    final structureSegments = _structureSegments(result);
    final vocalOutput = result?.vocalModelOutput ??
        (result == null
            ? null
            : VocalModelOutput(
                vocalTimestamps: result.vocalTimestamps,
                nonVocalOppositeSegments: result.nonVocalSegments,
                nonVocalPartSegments: result.nonVocalSegments,
                rawLog: '',
              ));
    final hasResults = result != null && result.stems.isNotEmpty;
    final isProcessing = musicProvider.whisperState == ProcessingState.preparing ||
        musicProvider.whisperState == ProcessingState.processing;

    final vocalsStem = result == null ? null : _stemFor(result, StemType.vocals);
    final instrumentalStem =
        result == null ? null : _stemFor(result, StemType.accompaniment);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBar(
        isRootTab: true,
        title: 'Vocal Remover',
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: AppLayout.pagePadding(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MethodPageHeader(
                methodLabel: 'Method 2',
                accentColor: AppColors.accentPink,
                icon: Icons.mic_external_on_rounded,
                title: 'Vocal Remover',
                subtitle:
                    'Split any song into acapella vocals and karaoke instrumental — 100% on your device.',
              ),
              const SizedBox(height: 24),
            if (selectedFile == null)
              _UploadPromptCard(
                isProcessing: isProcessing,
                onPickFile: _pickFile,
              )
            else ...[
              _SourceTrackCard(
                fileName: selectedFile.name,
                durationSeconds: durationSeconds,
                onChangeFile: _pickFile,
              ),
              const SizedBox(height: 20),
              if (!hasResults)
                isProcessing
                    ? _ProcessingCard(
                        progress: musicProvider.whisperProgress,
                        state: musicProvider.whisperState,
                        onTap: _openProcessingView,
                      )
                    : _SeparatePromptCard(onSeparate: _startSeparation)
              else ...[
                Text(
                  'Your separated tracks',
                  style: AppTextStyles.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Powered by ${_method2SeparationEngineLabel()} · structure via ${ProcessingConstants.svadModelLabel}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (vocalsStem != null)
                  VocalRemoverStemCard(
                    stem: vocalsStem,
                    title: 'Acapella',
                    subtitle: 'Vocals only',
                    durationSeconds: durationSeconds,
                    animationIndex: 0,
                    onDownload: () => downloadVocalRemoverStem(
                      stem: vocalsStem,
                      fileName: _downloadName(musicProvider, 'acapella'),
                      fileService: _fileService,
                      messenger: ScaffoldMessenger.of(context),
                    ),
                  ),
                if (instrumentalStem != null) ...[
                  const SizedBox(height: 16),
                  VocalRemoverStemCard(
                    stem: instrumentalStem,
                    title: 'Karaoke',
                    subtitle: 'Instrumental (no vocals)',
                    durationSeconds: durationSeconds,
                    animationIndex: 1,
                    onDownload: () => downloadVocalRemoverStem(
                      stem: instrumentalStem,
                      fileName: _downloadName(musicProvider, 'karaoke'),
                      fileService: _fileService,
                      messenger: ScaffoldMessenger.of(context),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: isProcessing ? null : _startSeparation,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Separate again'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.surfaceBorder),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                if (structureSegments.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _StructureExpansion(
                    expanded: _structureExpanded,
                    onExpansionChanged: (value) =>
                        setState(() => _structureExpanded = value),
                    structureSegments: structureSegments,
                    durationSeconds: durationSeconds,
                    playerPosition: playerProvider.currentPosition,
                    selectedSegmentId: _selectedSegment?.id,
                    vocalOutput: vocalOutput,
                    isBuildingGapless: _buildingGapless,
                    gaplessResult: _gaplessResult,
                    onCreateGapless: _createGaplessMix,
                    onPlayGapless:
                        _gaplessWavPath != null ? _playGaplessMix : null,
                    onSaveGapless:
                        _gaplessWavPath != null ? _saveGaplessMix : null,
                    onSegmentSelected: _selectSegment,
                    onSeek: playerProvider.seek,
                  ),
                ],
              ],
            ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 1,
        onTap: (index) => AppRoutes.onBottomNavTap(context, index),
      ),
    );
  }
}

class _UploadPromptCard extends StatelessWidget {
  const _UploadPromptCard({
    required this.isProcessing,
    required this.onPickFile,
  });

  final bool isProcessing;
  final VoidCallback onPickFile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.accentPink.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.upload_file_rounded,
            size: 48,
            color: AppColors.accentPink.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a song to begin',
            style: AppTextStyles.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'MP3, WAV, M4A and more — pick from files or share into Cliploops.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: 'Browse audio file',
            icon: Icons.folder_open_rounded,
            colors: const [AppColors.accentPink, AppColors.primaryPurple],
            isLoading: isProcessing,
            onPressed: isProcessing ? null : onPickFile,
          ),
        ],
      ),
    );
  }
}

class _SourceTrackCard extends StatelessWidget {
  const _SourceTrackCard({
    required this.fileName,
    required this.durationSeconds,
    required this.onChangeFile,
  });

  final String fileName;
  final double durationSeconds;
  final VoidCallback onChangeFile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryPurple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.audiotrack_rounded, color: AppColors.primaryPurple),
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
                    style: AppTextStyles.mono.copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChangeFile,
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

class _SeparatePromptCard extends StatelessWidget {
  const _SeparatePromptCard({required this.onSeparate});

  final VoidCallback onSeparate;

  @override
  Widget build(BuildContext context) {
    final engine = _method2SeparationEngineLabel();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accentPink.withValues(alpha: 0.12),
            AppColors.surfaceElevated,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accentPink.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            'Ready to separate',
            style: AppTextStyles.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'We will extract a clean acapella (vocals only) and karaoke '
            '(instruments only) using $engine, then analyse structure with SVAD. '
            'Tap Separate again after updates to refresh your stems.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: 'Separate song',
            icon: Icons.call_split_rounded,
            colors: const [AppColors.accentPink, AppColors.primaryPurple],
            onPressed: onSeparate,
          ),
        ],
      ),
    );
  }
}

class _ProcessingCard extends StatelessWidget {
  const _ProcessingCard({
    required this.progress,
    required this.state,
    required this.onTap,
  });

  final int progress;
  final ProcessingState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stepText = processingStepText(
      method: ActiveProcessingMethod.whisper,
      state: state,
      progress: progress,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.accentPink.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              ProgressIndicatorWidget(
                progress: progress,
                size: 120,
                strokeWidth: 8,
              ),
              const SizedBox(height: 18),
              Text(
                'Separating your song…',
                style: AppTextStyles.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                stepText,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Tap to view full progress · runs in background',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.accentPink.withValues(alpha: 0.85),
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StructureExpansion extends StatelessWidget {
  const _StructureExpansion({
    required this.expanded,
    required this.onExpansionChanged,
    required this.structureSegments,
    required this.durationSeconds,
    required this.playerPosition,
    required this.selectedSegmentId,
    required this.vocalOutput,
    required this.isBuildingGapless,
    required this.gaplessResult,
    required this.onCreateGapless,
    required this.onPlayGapless,
    required this.onSaveGapless,
    required this.onSegmentSelected,
    required this.onSeek,
  });

  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;
  final List<Segment> structureSegments;
  final double durationSeconds;
  final Duration playerPosition;
  final String? selectedSegmentId;
  final VocalModelOutput? vocalOutput;
  final bool isBuildingGapless;
  final GaplessMixResult? gaplessResult;
  final VoidCallback onCreateGapless;
  final VoidCallback? onPlayGapless;
  final VoidCallback? onSaveGapless;
  final void Function(Segment segment, {bool autoPlay}) onSegmentSelected;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: onExpansionChanged,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text('Song structure (${ProcessingConstants.svadModelLabel})'),
          subtitle: Text(
            'Prelude · Interlude · Postlude',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StructureDetectionSummary(segments: structureSegments),
                  if (durationSeconds > 0) ...[
                    const SizedBox(height: 16),
                    StructureTimeline(
                      durationSeconds: durationSeconds,
                      structureSegments: structureSegments,
                      position: playerPosition,
                      selectedSegmentId: selectedSegmentId,
                      onSegmentSelected: (segment) =>
                          onSegmentSelected(segment),
                      onSeek: onSeek,
                    ),
                  ],
                  const SizedBox(height: 16),
                  StructureSegmentList(
                    segments: structureSegments,
                    selectedSegmentId: selectedSegmentId,
                    onSegmentTap: (segment) => onSegmentSelected(segment),
                  ),
                  const SizedBox(height: 16),
                  GaplessMixPanel(
                    interludeCount: structureInterludeCount(structureSegments),
                    isBuilding: isBuildingGapless,
                    lastExport: gaplessResult,
                    onCreate: onCreateGapless,
                    onPlay: onPlayGapless,
                    onSave: onSaveGapless,
                  ),
                  if (vocalOutput != null) ...[
                    const SizedBox(height: 16),
                    VocalDetectionList(vocalOutput: vocalOutput!),
                    if (vocalOutput!.rawLog.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      RawModelOutputPanel(rawLog: vocalOutput!.rawLog),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
