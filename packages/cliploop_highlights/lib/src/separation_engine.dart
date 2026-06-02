import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'audio_decode.dart';
import 'models.dart';
import 'uvr_separation_service.dart';

/// Decode → UVR MDX-Net separation → vocals + instrumental stems on disk.
///
/// The entire pipeline (ffmpeg decode, STFT/ISTFT, NPU inference) runs in a
/// background isolate so the host app's UI never janks. Platform channels are
/// made available in the isolate via [BackgroundIsolateBinaryMessenger] (the QNN
/// delegate, path_provider, ffmpeg, and the ORT fallback all use channels).
class SeparationEngine {
  SeparationEngine._();
  static final SeparationEngine instance = SeparationEngine._();

  Future<SeparationStems> separate(
    String audioPath, {
    void Function(double progress)? onProgress,
  }) async {
    if (!await File(audioPath).exists()) {
      throw ArgumentError('cliploop_highlights: file not found — $audioPath');
    }

    final token = RootIsolateToken.instance;
    if (token == null) {
      // No root isolate (e.g. pure-Dart unit test) — run inline.
      return _runPipeline(audioPath, onProgress);
    }

    final rp = ReceivePort();
    final completer = Completer<SeparationStems>();
    void fail(Object e) {
      if (!completer.isCompleted) completer.completeError(e);
      rp.close();
    }

    rp.listen((dynamic msg) {
      if (msg is double) {
        onProgress?.call(msg);
      } else if (msg is SeparationStems) {
        if (!completer.isCompleted) completer.complete(msg);
        rp.close();
      } else if (msg is List) {
        // Isolate.spawn onError → [error, stack]; our catch → ['__err__', msg].
        fail(Exception(msg.isNotEmpty ? msg.last.toString() : 'separation failed'));
      } else if (msg == null) {
        // onExit with no prior result.
        fail(Exception('cliploop_highlights: separation isolate exited unexpectedly'));
      }
    });

    final isolate = await Isolate.spawn(
      _entry,
      _SeparateRequest(token: token, audioPath: audioPath, send: rp.sendPort),
      onError: rp.sendPort,
      onExit: rp.sendPort,
      errorsAreFatal: true,
      debugName: 'cliploop_separation',
    );
    return completer.future.whenComplete(isolate.kill);
  }

  static Future<void> _entry(_SeparateRequest req) async {
    BackgroundIsolateBinaryMessenger.ensureInitialized(req.token);
    final stems = await _runPipeline(
      req.audioPath,
      (p) => req.send.send(p),
    );
    req.send.send(stems);
  }

  static Future<SeparationStems> _runPipeline(
    String audioPath,
    void Function(double progress)? onProgress,
  ) async {
    final sw = Stopwatch()..start();
    final decoded = await decodeToWav16(audioPath);
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory('${tempDir.path}/cliploop_stems_${const Uuid().v4()}');
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

  static SeparationBackend _backend() {
    if (Platform.isAndroid) {
      return UvrSeparationService.instance.usingQnn
          ? SeparationBackend.hexagonNpu
          : SeparationBackend.cpu;
    }
    if (Platform.isIOS) return SeparationBackend.coreml;
    return SeparationBackend.cpu;
  }
}

class _SeparateRequest {
  const _SeparateRequest({
    required this.token,
    required this.audioPath,
    required this.send,
  });
  final RootIsolateToken token;
  final String audioPath;
  final SendPort send;
}
