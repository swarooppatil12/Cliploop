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
/// ffmpeg decode runs on the **main isolate** (ffmpeg_kit is not background-isolate
/// safe). The heavy work — STFT/ISTFT + NPU inference + WAV writes — runs in a
/// **spawned isolate** so it never janks the host UI. Channels used there (QNN
/// delegate, path_provider, ORT fallback) are enabled via
/// [BackgroundIsolateBinaryMessenger]. Progress streams back over a [SendPort].
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
    final sw = Stopwatch()..start();

    // 1) Decode on the MAIN isolate (ffmpeg_kit isn't background-isolate safe).
    final decoded = await decodeToWav16(audioPath);
    try {
      // 2) Resolve output paths on main (filesystem is shared across isolates).
      final tempDir = await getTemporaryDirectory();
      final dir = Directory('${tempDir.path}/cliploop_stems_${const Uuid().v4()}');
      await dir.create(recursive: true);
      final vocalsPath = '${dir.path}/vocals.wav';
      final instPath = '${dir.path}/instrumental.wav';

      // 3) Heavy separation in a background isolate (inline if no root isolate).
      final r = await _separate(decoded.path, vocalsPath, instPath, onProgress);
      sw.stop();

      return SeparationStems(
        vocalsPath: r.vocals,
        instrumentalPath: r.inst,
        sampleRate: r.sampleRate,
        durationSeconds: r.frameCount / r.sampleRate,
        backend: _backend(r.usedQnn),
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

  Future<_SepResult> _separate(
    String inWav,
    String vocalsOut,
    String instOut,
    void Function(double progress)? onProgress,
  ) async {
    final token = RootIsolateToken.instance;
    if (token == null) {
      return _runSeparation(inWav, vocalsOut, instOut, onProgress);
    }

    final rp = ReceivePort();
    final completer = Completer<_SepResult>();
    void fail(Object e) {
      if (!completer.isCompleted) completer.completeError(e);
      rp.close();
    }

    rp.listen((dynamic msg) {
      if (msg is double) {
        onProgress?.call(msg);
      } else if (msg is _SepResult) {
        if (!completer.isCompleted) completer.complete(msg);
        rp.close();
      } else if (msg is List) {
        fail(Exception(msg.isNotEmpty ? msg.last.toString() : 'separation failed'));
      } else if (msg == null) {
        fail(Exception('cliploop_highlights: separation isolate exited unexpectedly'));
      }
    });

    final isolate = await Isolate.spawn(
      _entry,
      _SepRequest(token, inWav, vocalsOut, instOut, rp.sendPort),
      onError: rp.sendPort,
      onExit: rp.sendPort,
      errorsAreFatal: true,
      debugName: 'cliploop_separation',
    );
    return completer.future.whenComplete(isolate.kill);
  }

  static Future<void> _entry(_SepRequest req) async {
    BackgroundIsolateBinaryMessenger.ensureInitialized(req.token);
    final r = await _runSeparation(
      req.inWav,
      req.vocalsOut,
      req.instOut,
      (p) => req.send.send(p),
    );
    req.send.send(r);
  }

  /// The heavy work: STFT + NPU/ORT inference + ISTFT + WAV writes. The input is
  /// an already-decoded 16-bit WAV (decode happened on the main isolate).
  static Future<_SepResult> _runSeparation(
    String inWav,
    String vocalsOut,
    String instOut,
    void Function(double progress)? onProgress,
  ) async {
    final result = await UvrSeparationService.instance.separateWavToFiles(
      wavPath: inWav,
      vocalsOutPath: vocalsOut,
      accompanimentOutPath: instOut,
      onProgress: (p) => onProgress?.call(p.clamp(0, 100) / 100.0),
    );
    return _SepResult(
      vocals: result.vocalsPath,
      inst: result.accompanimentPath,
      sampleRate: result.sampleRate,
      frameCount: result.frameCount,
      usedQnn: UvrSeparationService.instance.usingQnn,
    );
  }

  SeparationBackend _backend(bool usedQnn) {
    if (Platform.isAndroid) {
      return usedQnn ? SeparationBackend.hexagonNpu : SeparationBackend.cpu;
    }
    if (Platform.isIOS) return SeparationBackend.coreml;
    return SeparationBackend.cpu;
  }
}

class _SepRequest {
  const _SepRequest(
    this.token,
    this.inWav,
    this.vocalsOut,
    this.instOut,
    this.send,
  );
  final RootIsolateToken token;
  final String inWav;
  final String vocalsOut;
  final String instOut;
  final SendPort send;
}

class _SepResult {
  const _SepResult({
    required this.vocals,
    required this.inst,
    required this.sampleRate,
    required this.frameCount,
    required this.usedQnn,
  });
  final String vocals;
  final String inst;
  final int sampleRate;
  final int frameCount;
  final bool usedQnn;
}
