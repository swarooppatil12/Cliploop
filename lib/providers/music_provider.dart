import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/processing_constants.dart';
import '../core/utils/file_helper.dart';
import '../models/music_file.dart';
import '../models/separation_result.dart';
import '../models/whisper_result.dart';
import '../services/background_keep_alive_service.dart';
import '../services/file_service.dart';
import '../services/notification_service.dart';
import '../services/spleeter_service.dart';
import '../services/whisper_service.dart';

enum ProcessingState { idle, preparing, processing, complete, error }

enum ActiveProcessingMethod { none, spleeter, whisper }

class MusicProvider extends ChangeNotifier {
  MusicProvider({
    FileService? fileService,
    SpleeterService? spleeterService,
    WhisperService? whisperService,
    NotificationService? notificationService,
  })  : _fileService = fileService ?? FileService(),
        _spleeterService = spleeterService ?? SpleeterService(),
        _whisperService = whisperService ?? WhisperService(),
        _notificationService = notificationService ?? NotificationService();

  final FileService _fileService;
  final SpleeterService _spleeterService;
  final WhisperService _whisperService;
  final NotificationService _notificationService;

  List<MusicFile> recentFiles = [];
  MusicFile? selectedFile;
  SeparationResult? spleeterResult;
  WhisperResult? whisperResult;

  ProcessingState spleeterState = ProcessingState.idle;
  ProcessingState whisperState = ProcessingState.idle;

  int spleeterProgress = 0;
  int whisperProgress = 0;

  String selectedSpleeterModel = ProcessingConstants.defaultSeparationModel;
  String selectedWhisperVocalModel =
      ProcessingConstants.defaultMethod2VocalModel;

  bool spleeterNeedsRun = false;
  bool whisperNeedsRun = false;

  ActiveProcessingMethod activeProcessingMethod = ActiveProcessingMethod.none;

  String? _lastErrorMessage;
  bool _cancelRequested = false;
  Future<void>? _processingFuture;

  String? get lastErrorMessage => _lastErrorMessage;

  bool get hasValidSpleeterResult =>
      spleeterResult != null &&
      selectedFile != null &&
      spleeterResult!.musicFileId == selectedFile!.id;

  bool get hasValidWhisperResult =>
      whisperResult != null &&
      selectedFile != null &&
      whisperResult!.musicFileId == selectedFile!.id;

  bool get hasActiveProcessingJob => _processingFuture != null;

  bool get isWhisperProcessing =>
      whisperState == ProcessingState.preparing ||
      whisperState == ProcessingState.processing;

  bool get isSpleeterProcessing =>
      spleeterState == ProcessingState.preparing ||
      spleeterState == ProcessingState.processing;

  bool _isStaleProcessingState(ProcessingState state) {
    return (state == ProcessingState.preparing ||
            state == ProcessingState.processing) &&
        _processingFuture == null;
  }

  bool shouldRunSpleeter() {
    if (selectedFile == null) {
      return false;
    }
    if (_processingFuture != null &&
        activeProcessingMethod == ActiveProcessingMethod.spleeter) {
      return false;
    }
    if (_isStaleProcessingState(spleeterState)) {
      return spleeterNeedsRun || !hasValidSpleeterResult;
    }
    if (spleeterState == ProcessingState.preparing ||
        spleeterState == ProcessingState.processing) {
      return false;
    }
    return spleeterNeedsRun ||
        !hasValidSpleeterResult ||
        spleeterState == ProcessingState.error;
  }

  bool shouldRunWhisper() {
    if (selectedFile == null) {
      return false;
    }
    if (_processingFuture != null &&
        activeProcessingMethod == ActiveProcessingMethod.whisper) {
      return false;
    }
    if (_isStaleProcessingState(whisperState)) {
      return whisperNeedsRun || !hasValidWhisperResult;
    }
    if (whisperState == ProcessingState.preparing ||
        whisperState == ProcessingState.processing) {
      return false;
    }
    return whisperNeedsRun ||
        !hasValidWhisperResult ||
        whisperState == ProcessingState.error;
  }

  void markSpleeterNeedsRun() {
    spleeterNeedsRun = true;
    notifyListeners();
  }

  void markWhisperNeedsRun() {
    whisperNeedsRun = true;
    notifyListeners();
  }

  bool consumeSpleeterNeedsRun() {
    if (!spleeterNeedsRun) {
      return false;
    }
    spleeterNeedsRun = false;
    return true;
  }

  bool consumeWhisperNeedsRun() {
    if (!whisperNeedsRun) {
      return false;
    }
    whisperNeedsRun = false;
    return true;
  }

  /// Loads a track into the app library. Returns `true` when the song changed.
  Future<bool> loadFile(MusicFile file) async {
    await ensureBootstrapped();
    final stored = _fileService.isStoredInApp(file.path)
        ? file
        : await _fileService.importToAppLibrary(
            sourcePath: file.path,
            displayName: file.name,
            existingId: file.id,
          );

    final isNewTrack = selectedFile?.id != stored.id;
    selectedFile = stored;
    await _fileService.cacheFile(stored);
    await _fileService.saveSelectedFileId(stored.id);

    if (isNewTrack) {
      _resetForNewTrack();
    }

    await _refreshRecentFiles();
    notifyListeners();
    return isNewTrack;
  }

  Future<void> pickAndLoadFile() async {
    await ensureBootstrapped();
    final file = await _fileService.pickFile();
    if (file != null) {
      await loadFile(file);
    }
  }

  Future<void> removeRecentFile(MusicFile file) async {
    if (selectedFile?.id == file.id) {
      if (hasValidSpleeterResult) {
        await _deleteResultArtifacts(spleeterResult);
      }
      if (hasValidWhisperResult) {
        await _deleteResultArtifacts(whisperResult);
      }
      selectedFile = null;
      await _fileService.saveSelectedFileId(null);
      clearResults();
    }

    await _fileService.deleteFromAppLibrary(file);
    recentFiles.removeWhere((existing) => existing.id == file.id);
    await _fileService.saveRecentFiles(recentFiles);
    notifyListeners();
  }

  bool get isProcessing {
    return spleeterState == ProcessingState.preparing ||
        spleeterState == ProcessingState.processing ||
        whisperState == ProcessingState.preparing ||
        whisperState == ProcessingState.processing;
  }

  Future<void> loadFileFromPath(String path) async {
    await ensureBootstrapped();
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Shared audio file not found: $path');
    }

    final imported = await _fileService.importToAppLibrary(
      sourcePath: path,
      displayName: FileHelper.fileName(path),
    );
    await loadFile(imported);
  }

  /// Starts processing if needed. Safe to call from multiple screens; only one
  /// job runs at a time and continues when the processing UI is closed.
  Future<void> ensureProcessing(ActiveProcessingMethod method) {
    if (_processingFuture != null) {
      return _processingFuture!;
    }

    if (method == ActiveProcessingMethod.spleeter &&
        _isStaleProcessingState(spleeterState)) {
      spleeterState = ProcessingState.idle;
      spleeterProgress = 0;
    } else if (method == ActiveProcessingMethod.whisper &&
        _isStaleProcessingState(whisperState)) {
      whisperState = ProcessingState.idle;
      whisperProgress = 0;
    }

    final future = switch (method) {
      ActiveProcessingMethod.spleeter => _runSpleeterInternal(),
      ActiveProcessingMethod.whisper => _runWhisperInternal(),
      ActiveProcessingMethod.none => Future<void>.value(),
    };

    _processingFuture = future.whenComplete(() {
      _processingFuture = null;
      if (activeProcessingMethod == method) {
        activeProcessingMethod = ActiveProcessingMethod.none;
      }
      unawaited(BackgroundKeepAliveService.instance.release());
      unawaited(_notificationService.stopForegroundProcessing());
    });

    return _processingFuture!;
  }

  Future<void> runSpleeter() => ensureProcessing(ActiveProcessingMethod.spleeter);

  Future<void> runWhisper() => ensureProcessing(ActiveProcessingMethod.whisper);

  Future<void> _runSpleeterInternal() async {
    final file = selectedFile;
    if (file == null) {
      throw Exception('No file selected for Spleeter processing');
    }
    if (!shouldRunSpleeter()) {
      return;
    }

    spleeterNeedsRun = false;
    _lastErrorMessage = null;
    _cancelRequested = false;
    activeProcessingMethod = ActiveProcessingMethod.spleeter;
    spleeterState = ProcessingState.preparing;
    spleeterProgress = 1;
    notifyListeners();

    try {
      await BackgroundKeepAliveService.instance.acquire();
      spleeterProgress = 3;
      notifyListeners();

      await _notificationService.startForegroundProcessing(
        file.name,
        'Detecting song structure…',
      );
      spleeterProgress = 4;
      notifyListeners();

      _notificationService.showProgress(file.name, spleeterProgress);

      spleeterState = ProcessingState.processing;
      spleeterProgress = 5;
      notifyListeners();
      _notificationService.showProgress(file.name, spleeterProgress);

      spleeterResult = await _spleeterService.separateOnDevice(
        filePath: file.path,
        model: selectedSpleeterModel,
        musicFileId: file.id,
        onProgress: (progress) {
          if (_cancelRequested) {
            return;
          }
          spleeterProgress = progress.clamp(0, 100);
          _notificationService.showProgress(file.name, spleeterProgress);
          notifyListeners();
        },
      );

      if (_cancelRequested) {
        throw Exception('Processing cancelled');
      }

      spleeterState = ProcessingState.complete;
      spleeterProgress = 100;
      _notificationService.showProcessingComplete(
        file.name,
        'Method 1',
        routeName: NotificationService.method1CompletePayload,
      );
    } catch (error) {
      if (_cancelRequested) {
        spleeterState = ProcessingState.idle;
        spleeterProgress = 0;
      } else {
        _lastErrorMessage = error.toString();
        spleeterState = ProcessingState.error;
        _notificationService.showProcessingFailed(file.name, _lastErrorMessage!);
      }
    }

    notifyListeners();
  }

  Future<void> _runWhisperInternal() async {
    final file = selectedFile;
    if (file == null) {
      throw Exception('No file selected for Whisper analysis');
    }
    if (!shouldRunWhisper()) {
      if (kDebugMode) {
        debugPrint('[WhisperJob] skipped — shouldRunWhisper=false '
            '(state=$whisperState, needsRun=$whisperNeedsRun, '
            'hasResult=$hasValidWhisperResult)');
      }
      return;
    }

    whisperNeedsRun = false;
    _lastErrorMessage = null;
    _cancelRequested = false;
    activeProcessingMethod = ActiveProcessingMethod.whisper;
    whisperState = ProcessingState.preparing;
    whisperProgress = 1;
    notifyListeners();

    if (kDebugMode) {
      debugPrint('[WhisperJob] start file=${file.name}');
    }

    try {
      await BackgroundKeepAliveService.instance.acquire();
      whisperProgress = 3;
      notifyListeners();
      if (kDebugMode) {
        debugPrint('[WhisperJob] keep-alive acquired');
      }

      await _notificationService.startForegroundProcessing(
        file.name,
        'Separating vocals…',
      );
      whisperProgress = 4;
      notifyListeners();

      _notificationService.showProgress(file.name, whisperProgress);

      whisperState = ProcessingState.processing;
      whisperProgress = 5;
      notifyListeners();
      _notificationService.showProgress(file.name, whisperProgress);

      if (kDebugMode) {
        debugPrint('[WhisperJob] decoding + ML separation…');
      }

      whisperResult = await _whisperService.separateOnDevice(
        filePath: file.path,
        musicFileId: file.id,
        onProgress: (progress) {
          if (_cancelRequested) {
            return;
          }
          whisperProgress = progress.clamp(0, 100);
          _notificationService.showProgress(file.name, whisperProgress);
          notifyListeners();
        },
      );

      if (kDebugMode && whisperResult != null) {
        for (final stem in whisperResult!.stems) {
          debugPrint(
            '[Whisper] stem ${stem.id} → ${stem.audioPath} '
            '(${stem.durationSeconds.toStringAsFixed(1)}s)',
          );
        }
      }

      if (_cancelRequested) {
        throw Exception('Processing cancelled');
      }

      whisperState = ProcessingState.complete;
      whisperProgress = 100;
      if (kDebugMode) {
        debugPrint('[WhisperJob] complete stems=${whisperResult?.stems.length ?? 0}');
        debugPrint(
          '[WhisperJob] see [CliploopsTiming] and [CliploopsPipeline] above for scan timing',
        );
      }
      _notificationService.showProcessingComplete(
        file.name,
        'Vocal Remover',
        routeName: NotificationService.method2CompletePayload,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[WhisperJob] failed: $error');
      }
      if (_cancelRequested) {
        whisperState = ProcessingState.idle;
        whisperProgress = 0;
      } else {
        _lastErrorMessage = error.toString();
        whisperState = ProcessingState.error;
        _notificationService.showProcessingFailed(file.name, _lastErrorMessage!);
      }
    }

    notifyListeners();
  }

  void clearResults() {
    spleeterResult = null;
    whisperResult = null;
    spleeterState = ProcessingState.idle;
    whisperState = ProcessingState.idle;
    spleeterProgress = 0;
    whisperProgress = 0;
    _lastErrorMessage = null;
    _cancelRequested = false;
    activeProcessingMethod = ActiveProcessingMethod.none;
    notifyListeners();
  }

  void cancelProcessing({bool spleeter = true, bool whisper = true}) {
    _cancelRequested = true;
    if (spleeter) {
      spleeterState = ProcessingState.idle;
      spleeterProgress = 0;
    }
    if (whisper) {
      whisperState = ProcessingState.idle;
      whisperProgress = 0;
    }
    activeProcessingMethod = ActiveProcessingMethod.none;
    notifyListeners();
  }

  void setSpleeterModel(String model) {
    selectedSpleeterModel = ProcessingConstants.defaultSeparationModel;
    notifyListeners();
  }

  void setWhisperVocalModel(String model) {
    if (model != ProcessingConstants.defaultMethod2VocalModel) {
      return;
    }
    selectedWhisperVocalModel = model;
    notifyListeners();
  }

  Future<void> refreshRecentFiles() => _refreshRecentFiles();

  Future<void>? _bootstrapFuture;
  bool _bootstrapped = false;

  /// Loads tracks dir + recent files once JNI / path_provider is safe (see [AppBootstrap]).
  Future<void> ensureBootstrapped() {
    return _bootstrapFuture ??= _bootstrapOnce();
  }

  bool get isBootstrapped => _bootstrapped;

  Future<void> _bootstrapOnce() async {
    if (_bootstrapped) {
      return;
    }
    await _bootstrap();
    _bootstrapped = true;
  }

  Future<void> _bootstrap() async {
    try {
      await _fileService.tracksDirectory();
      await _refreshRecentFiles();
      await _restoreSelectedFile();
      await _migrateExternalLibraryEntries();
    } catch (error, stackTrace) {
      debugPrint('MusicProvider bootstrap failed: $error\n$stackTrace');
    }
  }

  Future<void> _migrateExternalLibraryEntries() async {
    var changed = false;
    final migrated = <MusicFile>[];

    for (final file in recentFiles) {
      if (_fileService.isStoredInApp(file.path)) {
        migrated.add(file);
        continue;
      }

      try {
        final stored = await _fileService.importToAppLibrary(
          sourcePath: file.path,
          displayName: file.name,
          existingId: file.id,
        );
        migrated.add(stored);
        changed = true;
        if (selectedFile?.id == file.id) {
          selectedFile = stored;
        }
      } catch (_) {
        changed = true;
      }
    }

    if (changed) {
      recentFiles = migrated;
      await _fileService.saveRecentFiles(recentFiles);
      notifyListeners();
    }
  }

  Future<void> _restoreSelectedFile() async {
    final selectedId = await _fileService.getSelectedFileId();
    if (selectedId == null) {
      return;
    }

    for (final file in recentFiles) {
      if (file.id == selectedId) {
        selectedFile = file;
        notifyListeners();
        return;
      }
    }

    await _fileService.saveSelectedFileId(null);
  }

  void _resetForNewTrack() {
    spleeterResult = null;
    whisperResult = null;
    spleeterState = ProcessingState.idle;
    whisperState = ProcessingState.idle;
    spleeterProgress = 0;
    whisperProgress = 0;
    _lastErrorMessage = null;
    _cancelRequested = false;
    spleeterNeedsRun = true;
    whisperNeedsRun = true;
  }

  Future<void> _refreshRecentFiles() async {
    recentFiles = await _fileService.getRecentFiles();
    notifyListeners();
  }

  Future<void> _deleteResultArtifacts(Object? result) async {
    final paths = <String>{};
    if (result is SeparationResult) {
      for (final stem in result.stems) {
        if (stem.audioPath.isNotEmpty) {
          paths.add(stem.audioPath);
        }
      }
    } else if (result is WhisperResult) {
      for (final stem in result.stems) {
        if (stem.audioPath.isNotEmpty) {
          paths.add(stem.audioPath);
        }
      }
    }

    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      final parent = file.parent;
      if (await parent.exists() &&
          parent.path.contains(AppConstants.stemsCacheDir)) {
        try {
          await parent.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}
