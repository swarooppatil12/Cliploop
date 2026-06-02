import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'audio_decode.dart';
import 'models.dart';
import 'uvr_separation_service.dart';

/// Decode → UVR MDX-Net separation → vocals + instrumental stems on disk.
/// Hexagon NPU on Android (TFLite + QNN), Core ML on iOS, CPU fallback.
class SeparationEngine {
  SeparationEngine._();
  static final SeparationEngine instance = SeparationEngine._();
  final _uuid = const Uuid();

  Future<SeparationStems> separate(
    String audioPath, {
    void Function(double progress)? onProgress,
  }) async {
    if (!await File(audioPath).exists()) {
      throw ArgumentError('cliploop_highlights: file not found — $audioPath');
    }
    final sw = Stopwatch()..start();
    final decoded = await decodeToWav16(audioPath);
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory('${tempDir.path}/cliploop_stems_${_uuid.v4()}');
      await dir.create(recursive: true);

      final result = await UvrSeparationService.instance.separateWavToFiles(
        wavPath: decoded.path,
        vocalsOutPath: '${dir.path}/vocals.wav',
        accompanimentOutPath: '${dir.path}/instrumental.wav',
        onProgress: (p) => onProgress?.call(p.clamp(0, 100) / 100.0),
      );
      sw.stop();

      return SeparationStems(
        vocalsPath: result.vocalsPath,
        instrumentalPath: result.accompanimentPath,
        sampleRate: result.sampleRate,
        durationSeconds: result.frameCount / result.sampleRate,
        backend: _backend(),
        wallMs: sw.elapsedMilliseconds,
      );
    } finally {
      if (decoded.isTemporary) {
        try {
          await File(decoded.path).delete();
        } catch (_) {}
      }
    }
  }

  SeparationBackend _backend() {
    if (Platform.isAndroid) {
      return UvrSeparationService.instance.usingQnn
          ? SeparationBackend.hexagonNpu
          : SeparationBackend.cpu;
    }
    if (Platform.isIOS) return SeparationBackend.coreml;
    return SeparationBackend.cpu;
  }
}
