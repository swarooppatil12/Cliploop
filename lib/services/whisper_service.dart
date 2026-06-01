import 'dart:async';
import 'dart:io';

import '../models/segment.dart';
import '../models/whisper_result.dart';
import 'local_audio_engine.dart';

/// On-device vocal separation + SVAD structure (Method 2 — vocal remover).
class WhisperService {
  WhisperService({LocalAudioEngine? engine})
      : _engine = engine ?? LocalAudioEngine();

  final LocalAudioEngine _engine;

  Future<WhisperResult> separateOnDevice({
    required String filePath,
    required String musicFileId,
    void Function(int progress)? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Audio file not found: $filePath');
    }

    return _engine.runWhisper(
      inputPath: filePath,
      musicFileId: musicFileId,
      onProgress: onProgress,
    );
  }

  Future<GaplessMixExport> exportGaplessMix({
    required String inputPath,
    required List<Segment> structureSegments,
    String? vocalsStemPath,
    String? drumsStemPath,
    int crossfadeMs = 80,
  }) {
    return _engine.exportGaplessMixWav(
      inputPath: inputPath,
      structureSegments: structureSegments,
      vocalsStemPath: vocalsStemPath,
      drumsStemPath: drumsStemPath,
      crossfadeMs: crossfadeMs,
    );
  }

  /// Emits progress updates while [separateOnDevice] runs on the caller side.
  Stream<int> progressWhile(Future<void> job) async* {
    var progress = 0;
    yield progress;

    final timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      progress = (progress + 2).clamp(0, 90);
    });

    try {
      await job;
      yield 100;
    } finally {
      timer.cancel();
    }
  }
}
