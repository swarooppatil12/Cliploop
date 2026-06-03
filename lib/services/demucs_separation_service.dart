import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../core/constants/processing_constants.dart';
import '../models/separation_file_result.dart';
import 'ml_model_service.dart';
import 'wav_stream_io.dart';

/// Legacy HT-Demucs ONNX separation (not used in the primary mobile pipeline).
/// Uses CPU inference on iOS to avoid CoreML / XNNPACK memory spikes.
class DemucsSeparationService {
  DemucsSeparationService._();

  static final DemucsSeparationService instance = DemucsSeparationService._();

  static const int sampleRate = ProcessingConstants.demucsSampleRate;
  static const int segmentSamples = ProcessingConstants.demucsSegmentSamples;
  static const int vocalsStemIndex = 3; // drums, bass, other, vocals

  final OnnxRuntime _runtime = OnnxRuntime();
  OrtSession? _vocalsSession;
  List<OrtProvider>? _cachedProviders;

  /// Loads the ONNX session (and model file) before decoding large audio files.
  Future<void> ensureReady({
    void Function(int downloadProgress)? onModelDownloadProgress,
  }) {
    return _ensureVocalsSession(onDownloadProgress: onModelDownloadProgress);
  }

  /// Separates a WAV on disk into vocals + accompaniment WAV files.
  ///
  /// Never loads the full song into memory — only one window at a time.
  Future<SeparationFileResult> separateWavToFiles({
    required String wavPath,
    required String vocalsOutPath,
    required String accompanimentOutPath,
    void Function(int progress)? onProgress,
    void Function(int downloadProgress)? onModelDownloadProgress,
  }) async {
    onProgress?.call(24);
    await _ensureVocalsSession(onDownloadProgress: onModelDownloadProgress);
    onProgress?.call(28);

    final info = await openWavStream(File(wavPath));
    if (info.sampleRate != sampleRate) {
      throw Exception(
        'Expected ${sampleRate}Hz WAV for separation, got ${info.sampleRate}Hz.',
      );
    }

    final vocalsWriter =
        await MonoWavWriter.create(vocalsOutPath, info.sampleRate);
    final instWriter =
        await MonoWavWriter.create(accompanimentOutPath, info.sampleRate);

    final window = Platform.isIOS
        ? ProcessingConstants.demucsIosWindowSamples
        : ProcessingConstants.demucsMobileWindowSamples;
    final overlap = Platform.isIOS
        ? ProcessingConstants.demucsIosWindowOverlap
        : ProcessingConstants.demucsMobileWindowOverlap;
    final stride = window - overlap;
    final windowCount =
        math.max(1, (info.frameCount + stride - 1) ~/ stride);

    Float32List? pendingVocals;
    Float32List? pendingInst;

    for (var windowIndex = 0; windowIndex < windowCount; windowIndex++) {
      final globalStart = windowIndex * stride;
      final windowFrames = math.min(window, info.frameCount - globalStart);
      if (windowFrames <= 0) {
        break;
      }

      final stereo = await readWavStereoWindow(
        info,
        globalStart,
        windowFrames,
      );

      final pass = await _separatePass(
        left: stereo.left,
        right: stereo.right,
      );

      final isLast = windowIndex == windowCount - 1;
      pendingVocals = await _streamWindowToWriter(
        writer: vocalsWriter,
        pass: pass['vocals']!,
        pending: pendingVocals,
        overlap: overlap,
        isLast: isLast,
      );
      pendingInst = await _streamWindowToWriter(
        writer: instWriter,
        pass: pass['accompaniment']!,
        pending: pendingInst,
        overlap: overlap,
        isLast: isLast,
      );

      onProgress?.call(28 + ((windowIndex + 1) * 47 ~/ windowCount));
      await Future<void>.delayed(Duration.zero);
    }

    if (pendingVocals != null && pendingVocals.isNotEmpty) {
      await vocalsWriter.writeFloat32Mono(pendingVocals);
    }
    if (pendingInst != null && pendingInst.isNotEmpty) {
      await instWriter.writeFloat32Mono(pendingInst);
    }

    await vocalsWriter.finalize();
    await instWriter.finalize();
    onProgress?.call(76);

    return SeparationFileResult(
      vocalsPath: vocalsOutPath,
      accompanimentPath: accompanimentOutPath,
      sampleRate: info.sampleRate,
      frameCount: info.frameCount,
    );
  }

  Future<void> dispose() async {
    await _vocalsSession?.close();
    _vocalsSession = null;
  }

  /// Cross-fades overlapping window tails and appends to the WAV writer.
  Future<Float32List?> _streamWindowToWriter({
    required MonoWavWriter writer,
    required Float32List pass,
    required Float32List? pending,
    required int overlap,
    required bool isLast,
  }) async {
    final len = pass.length;
    if (len == 0) {
      return pending;
    }

    if (pending == null) {
      if (isLast) {
        await writer.writeFloat32Mono(pass);
        return null;
      }
      final bodyEnd = len - overlap;
      if (bodyEnd > 0) {
        await writer.writeFloat32Mono(pass, length: bodyEnd);
      }
      return Float32List.fromList(pass.sublist(bodyEnd));
    }

    final blendLen = math.min(overlap, math.min(pending.length, len));
    if (blendLen > 0) {
      final blended = Float32List(blendLen);
      for (var i = 0; i < blendLen; i++) {
        final t = i / blendLen;
        blended[i] = pending[i] * (1.0 - t) + pass[i] * t;
      }
      await writer.writeFloat32Mono(blended);
    }

    if (isLast) {
      if (len > blendLen) {
        await writer.writeFloat32Mono(pass, offset: blendLen);
      }
      return null;
    }

    final bodyEnd = len - overlap;
    if (bodyEnd > blendLen) {
      await writer.writeFloat32Mono(
        pass,
        offset: blendLen,
        length: bodyEnd - blendLen,
      );
    }
    return Float32List.fromList(pass.sublist(bodyEnd));
  }

  Future<Map<String, Float32List>> _separatePass({
    required Float32List left,
    required Float32List right,
  }) async {
    final vocalsMono = Float32List(left.length);
    final instMono = Float32List(left.length);
    final vocalWeight = Float32List(left.length);
    final instWeight = Float32List(left.length);

    final overlap = (segmentSamples *
            ProcessingConstants.demucsOverlapFraction)
        .floor();
    final stride = segmentSamples - overlap;
    final chunkCount = math.max(1, (left.length + stride - 1) ~/ stride);
    final window = _transitionWindow(segmentSamples);
    final stemOffset = vocalsStemIndex * 2 * segmentSamples;

    for (var chunkIndex = 0; chunkIndex < chunkCount; chunkIndex++) {
      final start = chunkIndex * stride;
      final end = math.min(start + segmentSamples, left.length);
      final chunkLen = end - start;
      final chunkWindow = window.sublist(0, chunkLen);
      final input = await _buildChunkInput(left, right, start, end);

      try {
        final output = await _vocalsSession!.run({'mix': input});
        try {
          final stemsTensor = output['stems'];
          if (stemsTensor == null) {
            throw StateError('Demucs ONNX output missing "stems" tensor.');
          }

          await _accumulateVocalsChunkFromTensor(
            tensor: stemsTensor,
            stemOffset: stemOffset,
            vocalsMono: vocalsMono,
            vocalWeight: vocalWeight,
            left: left,
            right: right,
            instMono: instMono,
            instWeight: instWeight,
            start: start,
            chunkLen: chunkLen,
            window: chunkWindow,
          );
        } finally {
          for (final value in output.values) {
            value.dispose();
          }
        }
      } finally {
        input.dispose();
      }

      if (chunkIndex.isOdd) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    _normalizeOverlap(vocalsMono, vocalWeight);
    _normalizeOverlap(instMono, instWeight);
    _normalizeInPlace(vocalsMono);
    _normalizeInPlace(instMono);

    return {
      'vocals': vocalsMono,
      'accompaniment': instMono,
    };
  }

  Future<OrtSessionOptions> _mobileSessionOptions() async {
    final providers = await _mobileProviders();
    final threads = Platform.isIOS ? 1 : ProcessingConstants.demucsIntraOpThreads;
    return OrtSessionOptions(
      intraOpNumThreads: threads,
      interOpNumThreads: ProcessingConstants.demucsInterOpThreads,
      providers: providers,
      useArena: !Platform.isIOS,
    );
  }

  Future<List<OrtProvider>> _mobileProviders() async {
    if (_cachedProviders != null) {
      return _cachedProviders!;
    }

    // ORT >=1.24 reports providers (e.g. WEBGPU) that flutter_onnxruntime's enum
    // can't parse, making getAvailableProviders() throw. Tolerate that.
    List<OrtProvider> available;
    try {
      available = await _runtime.getAvailableProviders();
    } catch (error) {
      if (kDebugMode) debugPrint('Demucs getAvailableProviders failed: $error');
      available = const <OrtProvider>[];
    }
    final unknown = available.isEmpty;
    if (Platform.isIOS) {
      // CPU-only on iOS — CoreML/XNNPACK can exceed the ~3.4 GB process limit.
      _cachedProviders = [OrtProvider.CPU];
    } else if (Platform.isAndroid && (unknown || available.contains(OrtProvider.XNNPACK))) {
      _cachedProviders = [OrtProvider.XNNPACK, OrtProvider.CPU];
    } else {
      _cachedProviders = [OrtProvider.CPU];
    }

    if (kDebugMode) {
      debugPrint(
        'Demucs ONNX providers: ${_cachedProviders!.map((p) => p.name).join(", ")}',
      );
    }

    return _cachedProviders!;
  }

  Future<void> _ensureVocalsSession({
    void Function(int progress)? onDownloadProgress,
  }) async {
    if (_vocalsSession != null) {
      return;
    }
    final modelPath = await MlModelService.instance.ensureDemucsVocals(
      onProgress: onDownloadProgress,
    );
    final options = await _mobileSessionOptions();
    _vocalsSession = await _runtime.createSession(modelPath, options: options);
  }

  Future<void> _accumulateVocalsChunkFromTensor({
    required OrtValue tensor,
    required int stemOffset,
    required Float32List vocalsMono,
    required Float32List vocalWeight,
    required Float32List left,
    required Float32List right,
    required Float32List instMono,
    required Float32List instWeight,
    required int start,
    required int chunkLen,
    required Float32List window,
  }) async {
    final raw = await tensor.asFlattenedList();
    final vocalLeftBase = stemOffset;
    final vocalRightBase = stemOffset + segmentSamples;

    double vocalLeftAt(int sample) {
      if (raw is Float32List) {
        return raw[vocalLeftBase + sample];
      }
      if (raw is Uint8List) {
        final flat = raw.buffer.asFloat32List(
          raw.offsetInBytes,
          raw.lengthInBytes ~/ Float32List.bytesPerElement,
        );
        return flat[vocalLeftBase + sample];
      }
      return (raw[vocalLeftBase + sample] as num).toDouble();
    }

    double vocalRightAt(int sample) {
      if (raw is Float32List) {
        return raw[vocalRightBase + sample];
      }
      if (raw is Uint8List) {
        final flat = raw.buffer.asFloat32List(
          raw.offsetInBytes,
          raw.lengthInBytes ~/ Float32List.bytesPerElement,
        );
        return flat[vocalRightBase + sample];
      }
      return (raw[vocalRightBase + sample] as num).toDouble();
    }

    for (var sample = 0; sample < chunkLen; sample++) {
      final w = window[sample];
      final leftValue = vocalLeftAt(sample);
      final rightValue = vocalRightAt(sample);
      final vocal = (leftValue + rightValue) * 0.5;
      final index = start + sample;

      vocalsMono[index] += vocal * w;
      vocalWeight[index] += w;

      final instL = left[index] - leftValue;
      final instR = right[index] - rightValue;
      final instrumental = ((instL + instR) * 0.5).clamp(-1.0, 1.0);
      instMono[index] += instrumental * w;
      instWeight[index] += w;
    }
  }

  void _normalizeOverlap(Float32List samples, Float32List weight) {
    for (var i = 0; i < samples.length; i++) {
      final w = math.max(weight[i], 1e-8);
      samples[i] /= w;
    }
  }

  void _normalizeInPlace(Float32List samples) {
    var peak = 0.0;
    for (final sample in samples) {
      peak = math.max(peak, sample.abs());
    }
    if (peak < 1e-9) {
      return;
    }
    final scale = 0.95 / peak;
    for (var i = 0; i < samples.length; i++) {
      samples[i] *= scale;
    }
  }

  Future<OrtValue> _buildChunkInput(
    Float32List left,
    Float32List right,
    int start,
    int end,
  ) async {
    final paddedLen = segmentSamples;
    final flat = Float32List(2 * paddedLen);
    final chunkLen = end - start;

    for (var i = 0; i < chunkLen; i++) {
      flat[i] = left[start + i];
      flat[paddedLen + i] = right[start + i];
    }

    return OrtValue.fromList(flat, [1, 2, paddedLen]);
  }

  Float32List _transitionWindow(int segment) {
    final overlapFraction = ProcessingConstants.demucsOverlapFraction;
    final transition = (segment * overlapFraction).floor();
    final window = Float32List(segment);
    window.fillRange(0, segment, 1.0);

    for (var i = 0; i < transition; i++) {
      final fade = i / transition;
      window[i] = fade;
      window[segment - transition + i] = 1.0 - fade;
    }
    return window;
  }
}
