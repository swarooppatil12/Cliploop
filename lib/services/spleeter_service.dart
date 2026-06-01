import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';


import '../models/separation_result.dart';
import '../models/segment.dart';

import 'local_audio_engine.dart';

/// Method-1 wrapper — waveform preview, gapless mix, and vocal separation.
/// Delegates all heavy work to [LocalAudioEngine] (UVR MDX-NET on Android + iOS).
class SpleeterService {
  SpleeterService({LocalAudioEngine? engine})
      : _engine = engine ?? LocalAudioEngine();

  final LocalAudioEngine _engine;

  /// Generates a waveform preview for [path].
  Future<List<double>> generateWaveform(String path) async {
    if (!await File(path).exists()) return const [];
    final controller = PlayerController();
    try {
      final waveform = await controller.extractWaveformData(
        path: path,
        noOfSamples: 120,
      );
      return waveform.map((v) => v.clamp(0.0, 1.0)).toList();
    } catch (_) {
      return const [];
    } finally {
      controller.dispose();
    }
  }

  /// Runs on-device vocal separation (UVR MDX-NET).
  Future<SeparationResult> separateOnDevice({
    required String filePath,
    required String model,
    required String musicFileId,
    void Function(int progress)? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Audio file not found: $filePath');
    }

    final result = await _engine.runWhisper(
      inputPath: filePath,
      musicFileId: musicFileId,
      onProgress: onProgress,
    );

    return SeparationResult(
      musicFileId: musicFileId,
      stems: result.stems,
      stemTimestamps: result.vocalTimestamps,
      structureSegments: result.segments,
      vocalModelOutput: result.vocalModelOutput,
      processedAt: DateTime.now(),
      model: model,
    );
  }

  /// Exports a gapless mix WAV with interludes removed.
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
}
