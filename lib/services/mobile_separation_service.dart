import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants/processing_constants.dart';
import '../models/separation_file_result.dart';
import 'android_device_service.dart';
import 'sherpa_source_separation_service.dart';
import 'uvr_separation_service.dart';

/// Routes vocal separation to the best on-device engine per platform.
///
/// - **iOS:** [UvrSeparationService] — UVR MDX-NET 9482 via Core ML (Neural Engine).
/// - **Android Snapdragon:** [SherpaSourceSeparationService] — same UVR model via
///   sherpa-onnx native C++ with QNN (Hexagon HTP / NPU), Moises-style fast path.
/// - **Android fallback:** [UvrSeparationService] — identical streaming ONNX pipeline as iOS CPU.
class MobileSeparationService {
  MobileSeparationService._();

  static final MobileSeparationService instance = MobileSeparationService._();

  String _lastEngineLabel = ProcessingConstants.mobileSeparationModelLabel;

  /// User-facing label for the separation engine used on the last run.
  String get lastEngineLabel => _lastEngineLabel;

  Future<void> ensureReady({
    void Function(int downloadProgress)? onModelDownloadProgress,
  }) async {
    if (Platform.isIOS) {
      await UvrSeparationService.instance.ensureReady(
        onModelDownloadProgress: onModelDownloadProgress,
      );
      return;
    }

    final profile = await AndroidDeviceService.instance.getProfile();
    if (kDebugMode &&
        profile.isSnapdragon &&
        !profile.hasQnnLibs) {
      debugPrint(
        '[Separation] Snapdragon detected (${profile.socModel}) but QNN libs '
        'not bundled — will try qnn then fall back to xnnpack/cpu. '
        'Run scripts/copy_qnn_android_libs.sh to enable NPU.',
      );
    }
    await SherpaSourceSeparationService.instance.ensureReady(
      onModelDownloadProgress: onModelDownloadProgress,
      useSnapdragonAcceleration: profile.isSnapdragon,
    );
  }

  Future<SeparationFileResult> separateWavToFiles({
    required String wavPath,
    required String vocalsOutPath,
    required String accompanimentOutPath,
    void Function(int progress)? onProgress,
    void Function(int downloadProgress)? onModelDownloadProgress,
  }) async {
    if (Platform.isIOS) {
      _lastEngineLabel = ProcessingConstants.mobileSeparationModelLabel;
      return UvrSeparationService.instance.separateWavToFiles(
        wavPath: wavPath,
        vocalsOutPath: vocalsOutPath,
        accompanimentOutPath: accompanimentOutPath,
        onProgress: onProgress,
        onModelDownloadProgress: onModelDownloadProgress,
      );
    }

    final profile = await AndroidDeviceService.instance.getProfile();
    final stopwatch = Stopwatch()..start();

    try {
      final result =
          await SherpaSourceSeparationService.instance.separateWavToFiles(
        wavPath: wavPath,
        vocalsOutPath: vocalsOutPath,
        accompanimentOutPath: accompanimentOutPath,
        onProgress: onProgress,
        onModelDownloadProgress: onModelDownloadProgress,
        useSnapdragonAcceleration: profile.isSnapdragon,
      );

      stopwatch.stop();
      final provider = SherpaSourceSeparationService.instance.lastProvider;
      _lastEngineLabel = profile.isSnapdragon
          ? '${ProcessingConstants.mobileSeparationModelLabel} · $provider'
          : ProcessingConstants.mobileSeparationModelLabel;

      if (kDebugMode) {
        debugPrint(
          '[Separation] Android native UVR MDX-NET 9482 — '
          '${stopwatch.elapsed.inSeconds}s provider=$provider snapdragon=${profile.isSnapdragon}',
        );
      }

      if (profile.isSnapdragon &&
          stopwatch.elapsed.inSeconds >
              ProcessingConstants.androidSeparationTargetSeconds) {
        debugPrint(
          '[Separation] WARN: exceeded '
          '${ProcessingConstants.androidSeparationTargetSeconds}s Snapdragon target '
          '(${stopwatch.elapsed.inSeconds}s)',
        );
      }

      return result;
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint(
          '[Separation] native UVR failed after ${stopwatch.elapsed.inSeconds}s, '
          'Dart streaming fallback: $error\n$stack',
        );
      }
    }

    stopwatch.reset();
    stopwatch.start();
    final result = await UvrSeparationService.instance.separateWavToFiles(
      wavPath: wavPath,
      vocalsOutPath: vocalsOutPath,
      accompanimentOutPath: accompanimentOutPath,
      onProgress: onProgress,
      onModelDownloadProgress: onModelDownloadProgress,
      preferSnapdragonAcceleration: profile.isSnapdragon,
    );
    stopwatch.stop();

    _lastEngineLabel = '${ProcessingConstants.mobileSeparationModelLabel} (streaming)';

    if (kDebugMode) {
      debugPrint(
        '[Separation] Android Dart UVR fallback — ${stopwatch.elapsed.inSeconds}s',
      );
    }

    return result;
  }
}
