import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../core/constants/processing_constants.dart';
import '../models/separation_file_result.dart';
import 'ml_model_service.dart';
import 'spleeter_stft.dart';
import 'wav_stream_io.dart';

/// UVR MDX-NET vocal extraction (sherpa-onnx UVR_MDXNET_9482) — Android + iOS.
class UvrSeparationService {
  UvrSeparationService._();

  static final UvrSeparationService instance = UvrSeparationService._();

  static const int sampleRate = ProcessingConstants.defaultSampleRate;
  static const int hopLength = ProcessingConstants.uvrMdxnetHopLength;

  static int _outerChunkSeconds() {
    if (Platform.isAndroid) {
      return ProcessingConstants.uvrAndroidOuterChunkSeconds;
    }
    return ProcessingConstants.uvrOuterChunkSeconds;
  }

  static int _outerOverlapSeconds() {
    if (Platform.isAndroid) {
      return ProcessingConstants.uvrAndroidOuterOverlapSeconds;
    }
    return ProcessingConstants.uvrOuterOverlapSeconds;
  }

  OnnxRuntime? _runtime;
  OnnxRuntime get _ort => _runtime ??= OnnxRuntime();
  OrtSession? _session;
  String? _inputName;
  _UvrModelShape? _shape;
  SpleeterStft? _stftEngine;
  Float32List? _chunkL;
  Float32List? _chunkR;
  Float32List? _inputFlat;
  bool _preferSnapdragonAcceleration = false;

  Future<void> ensureReady({
    void Function(int downloadProgress)? onModelDownloadProgress,
  }) async {
    await _ensureSession(onDownloadProgress: onModelDownloadProgress);
  }

  Future<SeparationFileResult> separateWavToFiles({
    required String wavPath,
    required String vocalsOutPath,
    required String accompanimentOutPath,
    void Function(int progress)? onProgress,
    void Function(int downloadProgress)? onModelDownloadProgress,
    bool preferSnapdragonAcceleration = false,
  }) async {
    _preferSnapdragonAcceleration = preferSnapdragonAcceleration;
    onProgress?.call(24);
    await _ensureSession(onDownloadProgress: onModelDownloadProgress);
    final shape = _shape!;
    onProgress?.call(28);

    final info = await openWavStream(File(wavPath));
    if (info.sampleRate != sampleRate) {
      throw Exception('Expected ${sampleRate}Hz WAV, got ${info.sampleRate}Hz.');
    }
    if (info.channels < 2) {
      throw Exception('Expected stereo WAV for UVR separation.');
    }

    _initProcessingBuffers(shape);

    final totalLen = info.frameCount;
    var margin = sampleRate * _outerOverlapSeconds();
    var outerChunk = _outerChunkSeconds() * sampleRate;
    if (totalLen < outerChunk) {
      outerChunk = totalLen;
    }
    if (margin > outerChunk ~/ 2) {
      margin = outerChunk ~/ 2;
    }

    final segments = _buildSegments(totalLen, outerChunk, margin);

    if (kDebugMode) {
      debugPrint(
        '[UVR] segmented MDXNET — ${segments.length} windows, $totalLen frames, '
        'providers=${await _uvrProviderLabel()}',
      );
    }

    onProgress?.call(32);

    final vocalsWriter = await MonoWavWriter.create(vocalsOutPath, sampleRate);
    final instWriter = await MonoWavWriter.create(accompanimentOutPath, sampleRate);

    var writePos = 0;
    var peak = 0.0;

    for (var si = 0; si < segments.length; si++) {
      final (segStart, segEnd) = segments[si];
      final segFrames = segEnd - segStart;
      final stereo = await readWavStereoWindow(info, segStart, segFrames);

      final out = await _processStereoWindow(
        left: stereo.left,
        right: stereo.right,
        shape: shape,
      );

      final copyStart = si == 0 ? 0 : margin;
      final copyEnd =
          si == segments.length - 1 ? out.left.length : out.left.length - margin;
      final len = copyEnd - copyStart;
      if (len > 0) {
        final monoVocals = Float32List(len);
        final monoAccompaniment = Float32List(len);
        for (var i = 0; i < len; i++) {
          final src = copyStart + i;
          final vocal = (out.left[src] + out.right[src]) * 0.5;
          final instL = stereo.left[src] - out.left[src];
          final instR = stereo.right[src] - out.right[src];
          final inst = (instL + instR) * 0.5;
          monoVocals[i] = vocal;
          monoAccompaniment[i] = inst;
          final vAbs = vocal.abs();
          final iAbs = inst.abs();
          if (vAbs > peak) peak = vAbs;
          if (iAbs > peak) peak = iAbs;
        }
        await vocalsWriter.writeFloat32Mono(monoVocals);
        await instWriter.writeFloat32Mono(monoAccompaniment);
        writePos += len;
      }

      onProgress?.call(32 + ((si + 1) * 40 ~/ segments.length));
      await Future<void>.delayed(Duration.zero);
    }

    onProgress?.call(74);

    await vocalsWriter.finalize();
    await instWriter.finalize();

    if (peak > 1e-9) {
      final gain = 0.95 / peak;
      await scaleMonoWavInPlace(vocalsOutPath, gain);
      await scaleMonoWavInPlace(accompanimentOutPath, gain);
    }

    if (kDebugMode) {
      debugPrint(
        '[UVR] Done — peak=$peak len=$writePos',
      );
    }

    onProgress?.call(76);

    return SeparationFileResult(
      vocalsPath: vocalsOutPath,
      accompanimentPath: accompanimentOutPath,
      sampleRate: info.sampleRate,
      frameCount: info.frameCount,
    );
  }

  void _initProcessingBuffers(_UvrModelShape shape) {
    _stftEngine ??= SpleeterStft(
      SpleeterStftConfig(
        nFft: shape.nFft,
        hopLength: hopLength,
        winLength: shape.nFft,
        center: true,
      ),
    );
    _chunkL ??= Float32List(shape.chunkSize);
    _chunkR ??= Float32List(shape.chunkSize);
    _inputFlat ??= Float32List(shape.dimC * shape.dimF * shape.dimT);
  }

  List<(int start, int end)> _buildSegments(int total, int chunkSize, int margin) {
    final out = <(int, int)>[];
    for (var skip = 0; skip < total; skip += chunkSize) {
      final start = math.max(0, skip - margin);
      final end = math.min(skip + chunkSize + margin, total);
      out.add((start, end));
      if (end == total) {
        break;
      }
    }
    return out;
  }

  /// UVR on one stereo window (streaming ONNX steps inside the window).
  Future<({Float32List left, Float32List right})> _processStereoWindow({
    required Float32List left,
    required Float32List right,
    required _UvrModelShape shape,
  }) async {
    final trim = shape.nFft ~/ 2;
    final genSize = shape.genSize;
    final chunkSize = shape.chunkSize;
    final numSamples = left.length;
    final pad = genSize - (numSamples % genSize);

    final assembledL = Float32List(numSamples);
    final assembledR = Float32List(numSamples);
    var pos = 0;

    for (var mixStep = 0; mixStep < numSamples + pad; mixStep += genSize) {
      final audioStart = math.max(0, mixStep - trim);
      final audioEnd = math.min(numSamples, mixStep + chunkSize - trim);
      final readLen = audioEnd - audioStart;

      final chunkL = _chunkL!;
      final chunkR = _chunkR!;
      chunkL.fillRange(0, chunkSize, 0);
      chunkR.fillRange(0, chunkSize, 0);

      if (readLen > 0) {
        final destOff = audioStart + trim - mixStep;
        chunkL.setRange(destOff, destOff + readLen, left, audioStart);
        chunkR.setRange(destOff, destOff + readLen, right, audioStart);
      }

      final (vL, vR) = await _runOnnxChunk(
        stftEngine: _stftEngine!,
        leftChunk: chunkL,
        rightChunk: chunkR,
        shape: shape,
        trim: trim,
        genSize: genSize,
        inputFlat: _inputFlat!,
      );

      final copyLen = math.min(vL.length, assembledL.length - pos);
      if (copyLen > 0) {
        assembledL.setRange(pos, pos + copyLen, vL, 0);
        assembledR.setRange(pos, pos + copyLen, vR, 0);
        pos += copyLen;
      }
    }

    if (pos == 0) {
      return (left: Float32List(left.length), right: Float32List(right.length));
    }

    return (left: assembledL, right: assembledR);
  }

  Future<String> _uvrProviderLabel() async {
    final providers = await _uvrProviders();
    return providers.map((p) => p.name).join(', ');
  }

  /// Runs ONNX on a single [chunkSize]-sample stereo chunk.
  /// Returns vocal (left, right) each [genSize] samples (trim removed).
  Future<(Float32List vL, Float32List vR)> _runOnnxChunk({
    required SpleeterStft stftEngine,
    required Float32List leftChunk,
    required Float32List rightChunk,
    required _UvrModelShape shape,
    required int trim,
    required int genSize,
    Float32List? inputFlat,
  }) async {
    final stftL = stftEngine.computeStft(leftChunk);
    final stftR = stftEngine.computeStft(rightChunk);

    if (stftL.numFrames == 0) {
      return (Float32List(genSize), Float32List(genSize));
    }

    if (stftL.numFrames != shape.dimT) {
      throw StateError(
        '[UVR] STFT frames=${stftL.numFrames} expected=${shape.dimT} '
        'chunk=${leftChunk.length}',
      );
    }

    final useDimT = shape.dimT;
    final flat = inputFlat ?? Float32List(shape.dimC * shape.dimF * useDimT);
    _writeUvrInput(flat, stftL, stftR, shape, useDimT);

    OrtValue? input;
    try {
      input = await OrtValue.fromList(flat, [1, shape.dimC, shape.dimF, useDimT]);
      final result = await _session!.run({_inputName!: input});
      try {
        final outputFlat = await _tensorToFloat32List(result.values.first);
        return _reconstructVocalPair(
          outputFlat: outputFlat,
          stftEngine: stftEngine,
          shape: shape,
          trim: trim,
          genSize: genSize,
          useDimT: useDimT,
        );
      } finally {
        for (final v in result.values) {
          v.dispose();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[UVR] ONNX error: $e');
      return (Float32List(genSize), Float32List(genSize));
    } finally {
      input?.dispose();
    }
  }

  /// Reconstructs vocal L/R from ONNX complex-spectrogram output [1,4,F,T].
  (Float32List vL, Float32List vR) _reconstructVocalPair({
    required Float32List outputFlat,
    required SpleeterStft stftEngine,
    required _UvrModelShape shape,
    required int trim,
    required int genSize,
    required int useDimT,
  }) {
    final chStride = shape.dimF * useDimT;
    if (outputFlat.length < 4 * chStride) {
      return (Float32List(genSize), Float32List(genSize));
    }

    // Model returns vocal complex STFT; zero-pad Nyquist bin before ISTFT.
    final specL = _extractComplex(
      outputFlat,
      realCh: 0,
      imagCh: 1,
      shape: shape,
      useDimT: useDimT,
    );
    final specR = _extractComplex(
      outputFlat,
      realCh: 2,
      imagCh: 3,
      shape: shape,
      useDimT: useDimT,
    );

    final rawL = stftEngine.computeIstft(specL);
    final rawR = stftEngine.computeIstft(specR);
    return (_trimCrop(rawL, trim, genSize), _trimCrop(rawR, trim, genSize));
  }

  Float32List _trimCrop(Float32List raw, int trim, int genSize) {
    if (raw.isEmpty) return Float32List(genSize);
    final s = trim.clamp(0, raw.length);
    final e = (raw.length - trim).clamp(s, raw.length);
    final trimmed = Float32List.sublistView(raw, s, e);
    if (trimmed.length >= genSize) return Float32List.sublistView(trimmed, 0, genSize);
    final out = Float32List(genSize);
    out.setRange(0, trimmed.length, trimmed);
    return out;
  }

  /// Reads ONNX output in [freq, time] layout into STFT [time, freq] buffers.
  SpleeterStftResult _extractComplex(
    Float32List flat, {
    required int realCh,
    required int imagCh,
    required _UvrModelShape shape,
    required int useDimT,
  }) {
    final bins = shape.nBins;
    final chStride = shape.dimF * useDimT;
    final real = Float32List(useDimT * bins);
    final imag = Float32List(useDimT * bins);
    final rb = realCh * chStride;
    final ib = imagCh * chStride;

    for (var f = 0; f < shape.dimF; f++) {
      for (var t = 0; t < useDimT; t++) {
        final idx = t * bins + f;
        real[idx] = flat[rb + f * useDimT + t];
        imag[idx] = flat[ib + f * useDimT + t];
      }
    }
    // Nyquist bin (dim_f .. n_bins-1) stays zero — matches sherpa-onnx freq_pad.
    return SpleeterStftResult(numFrames: useDimT, real: real, imag: imag);
  }

  void _writeUvrInput(
    Float32List dest,
    SpleeterStftResult stftL,
    SpleeterStftResult stftR,
    _UvrModelShape shape,
    int useDimT,
  ) {
    var o = 0;
    o = _writeSpecChannel(dest, o, stftL, shape, useDimT, real: true);
    o = _writeSpecChannel(dest, o, stftL, shape, useDimT, real: false);
    o = _writeSpecChannel(dest, o, stftR, shape, useDimT, real: true);
    _writeSpecChannel(dest, o, stftR, shape, useDimT, real: false);
  }

  /// ONNX expects [batch, channel, freq, time] — iterate freq then time.
  int _writeSpecChannel(
    Float32List dest,
    int offset,
    SpleeterStftResult stft,
    _UvrModelShape shape,
    int useDimT, {
    required bool real,
  }) {
    final bins = shape.nBins;
    for (var f = 0; f < shape.dimF; f++) {
      for (var t = 0; t < useDimT; t++) {
        final frameBase = t * bins;
        dest[offset++] =
            real ? stft.real[frameBase + f] : stft.imag[frameBase + f];
      }
    }
    return offset;
  }

  Future<void> _ensureSession({
    void Function(int progress)? onDownloadProgress,
  }) async {
    if (_session != null && _shape != null) return;

    final modelPath = await MlModelService.instance.ensureUvrMdxnet(
      onProgress: onDownloadProgress,
    );

    _session = await _openSession(modelPath);
    _inputName = _session!.inputNames.first;

    final dimC = ProcessingConstants.uvrMdxnetDimC;
    var dimF = ProcessingConstants.uvrMdxnetDimF;
    var dimT = ProcessingConstants.uvrMdxnetDimT;
    final nFft = ProcessingConstants.uvrMdxnetNFft;

    try {
      final outputInfo = await _session!.getOutputInfo();
      if (outputInfo.isNotEmpty) {
        final rawShape = outputInfo.first['shape'];
        if (rawShape is List && rawShape.length >= 4) {
          dimF = (rawShape[2] as num).toInt();
          dimT = (rawShape[3] as num).toInt();
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[UVR] getOutputInfo failed — using baked dims: $error');
      }
    }

    if (dimC != 4) {
      throw StateError('[UVR] Unexpected dim_c=$dimC (expected 4)');
    }

    // sherpa-onnx: chunkSize = hop * (dimT-1), genSize = chunkSize - nFft
    final chunkSize = hopLength * (dimT - 1);
    final genSize = chunkSize - nFft;

    _shape = _UvrModelShape(
      dimC: dimC,
      dimF: dimF,
      dimT: dimT,
      nFft: nFft,
      chunkSize: chunkSize,
      genSize: genSize,
    );

    if (kDebugMode) {
      debugPrint(
        '[UVR] ready: dimF=$dimF dimT=$dimT nFft=$nFft '
        'chunkSize=$chunkSize genSize=$genSize center=true',
      );
    }
  }

  int get _uvrIntraOpThreads {
    if (Platform.isAndroid) {
      return ProcessingConstants.uvrAndroidIntraOpThreads;
    }
    return ProcessingConstants.uvrDartIntraOpThreads;
  }

  Future<OrtSession> _openSession(String modelPath) async {
    final threads = _uvrIntraOpThreads;
    final options = (List<OrtProvider> providers) => OrtSessionOptions(
          intraOpNumThreads: threads,
          interOpNumThreads: 1,
          providers: providers,
          useArena: false,
        );

    final providers = await _uvrProviders();
    try {
      return await _ort.createSession(modelPath, options: options(providers));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[UVR] session open failed ($providers), CPU fallback: $error');
      }
      return _ort.createSession(
        modelPath,
        options: options([OrtProvider.CPU]),
      );
    }
  }

  Future<List<OrtProvider>> _uvrProviders() async {
    final available = await _ort.getAvailableProviders();

    if (Platform.isIOS &&
        !ProcessingConstants.uvrDartPreferCpuOnIos &&
        ProcessingConstants.uvrDartUseCoreMlOnIos &&
        available.contains(OrtProvider.CORE_ML)) {
      return [OrtProvider.CORE_ML, OrtProvider.CPU];
    }

    if (Platform.isAndroid) {
      if (_preferSnapdragonAcceleration &&
          available.contains(OrtProvider.QNN)) {
        return [OrtProvider.QNN, OrtProvider.XNNPACK, OrtProvider.CPU];
      }
      if (available.contains(OrtProvider.XNNPACK)) {
        return [OrtProvider.XNNPACK, OrtProvider.CPU];
      }
    }

    return [OrtProvider.CPU];
  }

  Future<Float32List> _tensorToFloat32List(OrtValue tensor) async {
    final raw = await tensor.asFlattenedList();
    if (raw is Float32List) {
      return raw;
    }
    if (raw is Uint8List) {
      return raw.buffer.asFloat32List(
        raw.offsetInBytes,
        raw.lengthInBytes ~/ Float32List.bytesPerElement,
      );
    }
    final out = Float32List(raw.length);
    for (var i = 0; i < raw.length; i++) {
      out[i] = (raw[i] as num).toDouble();
    }
    return out;
  }
}

class _UvrModelShape {
  const _UvrModelShape({
    required this.dimC,
    required this.dimF,
    required this.dimT,
    required this.nFft,
    required this.chunkSize,
    required this.genSize,
  });

  final int dimC;
  final int dimF;
  final int dimT;
  final int nFft;

  /// hop * (dimT - 1) — audio window per ONNX call (center STFT).
  final int chunkSize;

  /// chunkSize - nFft — useful samples after ISTFT edge trim.
  final int genSize;

  /// Full spectrum bins: nFft/2 + 1 (DC through Nyquist).
  int get nBins => nFft ~/ 2 + 1;
}
