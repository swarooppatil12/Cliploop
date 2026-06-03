import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart';

import '../core/constants/processing_constants.dart';
import '../core/utils/region_utils.dart';
import 'ml_model_service.dart';
import 'sherpa_bindings.dart';

/// Open-source Silero VAD (ONNX) — voice activity for structure detection.
///
/// Tuned for sung vocals (Tamil/Indian film songs, etc.), not only speech.
/// Uses a strict primary pass; a softer secondary pass only when coverage is low.
class SileroVadService {
  SileroVadService._();

  static final SileroVadService instance = SileroVadService._();

  static const int vadSampleRate = 16000;

  /// Returns vocal-present regions as `(startSeconds, endSeconds)` in song time.
  Future<List<(double, double)>> detectVocalRegions({
    required Float32List mono,
    required int sourceSampleRate,
    void Function(int downloadProgress)? onModelDownloadProgress,
  }) async {
    ensureSherpaBindings();

    final modelPath = await MlModelService.instance.ensureSileroVad(
      onProgress: onModelDownloadProgress,
    );

    final resampled = _resample(mono, sourceSampleRate, vadSampleRate);
    if (resampled.isEmpty) {
      return [];
    }

    final durationSeconds = resampled.length / vadSampleRate;

    final primary = await _runPass(
      resampled: resampled,
      durationSeconds: durationSeconds,
      modelPath: modelPath,
      threshold: ProcessingConstants.sileroVadPrimaryThreshold,
    );

    final primaryCoverage = coverageFraction(primary, durationSeconds);
    if (primaryCoverage >= ProcessingConstants.minVadCoverageFraction) {
      return RegionUtils.merge(
        primary,
        gap: ProcessingConstants.vocalRegionMergeGapSeconds,
      );
    }

    final secondary = await _runPass(
      resampled: resampled,
      durationSeconds: durationSeconds,
      modelPath: modelPath,
      threshold: ProcessingConstants.sileroVadSecondaryThreshold,
    );

    final merged = <(double, double)>[...primary, ...secondary];
    return RegionUtils.merge(
      merged,
      gap: ProcessingConstants.vocalRegionMergeGapSeconds,
    );
  }

  Future<List<(double, double)>> _runPass({
    required Float32List resampled,
    required double durationSeconds,
    required String modelPath,
    required double threshold,
  }) async {
    final config = VadModelConfig(
      sileroVad: SileroVadModelConfig(
        model: modelPath,
        threshold: threshold,
        minSilenceDuration: 0.42,
        minSpeechDuration: 0.28,
        maxSpeechDuration: math.max(180.0, durationSeconds + 10),
      ),
      sampleRate: vadSampleRate,
      numThreads: 2,
      debug: false,
    );

    final vad = VoiceActivityDetector(
      config: config,
      bufferSizeInSeconds: durationSeconds + 8,
    );

    try {
      vad.acceptWaveform(resampled);
      vad.flush();

      final regions = <(double, double)>[];
      while (!vad.isEmpty()) {
        final segment = vad.front();
        final startSec = segment.start / vadSampleRate;
        final endSec =
            (segment.start + segment.samples.length) / vadSampleRate;
        vad.pop();

        if (endSec - startSec >= ProcessingConstants.minVocalRegionSeconds) {
          regions.add((startSec, endSec));
        }
      }

      return regions;
    } finally {
      vad.free();
    }
  }

  static double coverageFraction(
    List<(double, double)> regions,
    double durationSeconds,
  ) {
    if (durationSeconds <= 0 || regions.isEmpty) {
      return 0;
    }
    var covered = 0.0;
    for (final (start, end) in regions) {
      covered += math.max(0, end - start);
    }
    return (covered / durationSeconds).clamp(0.0, 1.0);
  }

  static Float32List _resample(
    Float32List input,
    int fromRate,
    int toRate,
  ) {
    if (fromRate == toRate || input.isEmpty) {
      return input;
    }

    final ratio = toRate / fromRate;
    final outLength = (input.length * ratio).floor();
    if (outLength <= 0) {
      return Float32List(0);
    }

    final output = Float32List(outLength);
    for (var i = 0; i < outLength; i++) {
      final srcPos = i / ratio;
      final index = srcPos.floor();
      final frac = srcPos - index;
      final a = input[index.clamp(0, input.length - 1)];
      final b = input[math.min(index + 1, input.length - 1)];
      output[i] = a * (1 - frac) + b * frac;
    }
    return output;
  }
}
