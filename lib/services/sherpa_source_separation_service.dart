import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/processing_constants.dart';
import '../models/separation_file_result.dart';
import 'ml_model_service.dart';
import 'sherpa_source_separation_bindings.dart';
import 'wav_stream_io.dart';

/// Fast on-device separation via sherpa-onnx native C++ (UVR or Spleeter).
///
/// Avoids per-chunk Dart STFT + flutter_onnxruntime — typically 5–15× faster
/// than [UvrSeparationService] on iOS for full songs.
class SherpaSourceSeparationService {
  SherpaSourceSeparationService._();

  static final SherpaSourceSeparationService instance =
      SherpaSourceSeparationService._();

  Pointer<SherpaOnnxOfflineSourceSeparation>? _uvrPtr;
  Pointer<SherpaOnnxOfflineSourceSeparation>? _spleeterPtr;

  Future<void> ensureReady({
    void Function(int downloadProgress)? onModelDownloadProgress,
  }) async {
    SherpaSourceSeparationBindings.instance.ensureInitialized();
    await _ensureUvr(onDownloadProgress: onModelDownloadProgress);
  }

  Future<SeparationFileResult> separateWavToFiles({
    required String wavPath,
    required String vocalsOutPath,
    required String accompanimentOutPath,
    void Function(int progress)? onProgress,
    void Function(int downloadProgress)? onModelDownloadProgress,
  }) async {
    SherpaSourceSeparationBindings.instance.ensureInitialized();
    onProgress?.call(24);

    final info = await openWavStream(File(wavPath));
    if (info.sampleRate != ProcessingConstants.defaultSampleRate) {
      throw Exception(
        'Expected ${ProcessingConstants.defaultSampleRate}Hz WAV, got ${info.sampleRate}Hz.',
      );
    }
    if (info.channels < 2) {
      throw Exception('Expected stereo WAV for source separation.');
    }

    onProgress?.call(28);

    // UVR first — best vocal isolation for SVAD / structure (matches prior pipeline).
    try {
      final uvr = await _ensureUvr(onDownloadProgress: onModelDownloadProgress);
      if (kDebugMode) {
        debugPrint('[Separation] native UVR (${info.frameCount} frames)');
      }
      return await _runNative(
        ptr: uvr,
        wavPath: wavPath,
        info: info,
        vocalsOutPath: vocalsOutPath,
        accompanimentOutPath: accompanimentOutPath,
        onProgress: onProgress,
        progressStart: 32,
        progressEnd: 76,
      );
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[Separation] UVR native failed: $error\n$stack');
      }
    }

    // Spleeter fallback — much faster when UVR cannot run (e.g. OOM).
    final spleeter = await _tryEnsureSpleeter(
      onDownloadProgress: onModelDownloadProgress,
    );
    if (spleeter == null) {
      throw StateError('Native source separation failed (UVR and Spleeter).');
    }
    if (kDebugMode) {
      debugPrint('[Separation] native Spleeter fallback (${info.frameCount} frames)');
    }
    return _runNative(
      ptr: spleeter,
      wavPath: wavPath,
      info: info,
      vocalsOutPath: vocalsOutPath,
      accompanimentOutPath: accompanimentOutPath,
      onProgress: onProgress,
      progressStart: 32,
      progressEnd: 76,
    );
  }

  Future<SeparationFileResult> _runNative({
    required Pointer<SherpaOnnxOfflineSourceSeparation> ptr,
    required String wavPath,
    required WavStreamInfo info,
    required String vocalsOutPath,
    required String accompanimentOutPath,
    void Function(int progress)? onProgress,
    required int progressStart,
    required int progressEnd,
  }) async {
    final bindings = SherpaSourceSeparationBindings.instance;
    onProgress?.call(progressStart + 2);

    final stereo = await loadStereoFromWav(wavPath);
    onProgress?.call(progressStart + 8);

    final n = stereo.left.length;
    final channelPtrs = calloc<Pointer<Float>>(2);
    final leftNative = calloc<Float>(n);
    final rightNative = calloc<Float>(n);
    leftNative.asTypedList(n).setAll(0, stereo.left);
    rightNative.asTypedList(n).setAll(0, stereo.right);
    channelPtrs[0] = leftNative;
    channelPtrs[1] = rightNative;

    Pointer<SherpaOnnxSourceSeparationOutput>? output;
    try {
      output = bindings.process(
        ptr,
        channelPtrs,
        2,
        n,
        info.sampleRate,
      );
      if (output == nullptr) {
        throw StateError('SherpaOnnxOfflineSourceSeparationProcess returned null');
      }

      onProgress?.call(progressStart + 20);

      final out = output.ref;
      if (out.numStems < 2) {
        throw StateError('Expected 2 stems, got ${out.numStems}');
      }

      final stems = out.stems;
      final vocalsMono = _stemToMono(stems + 0);
      final instMono = _stemToMono(stems + 1);

      onProgress?.call(progressStart + 40);

      var vocalPeak = 0.0;
      var instPeak = 0.0;
      for (var i = 0; i < vocalsMono.length; i++) {
        final v = vocalsMono[i].abs();
        final ins = instMono[i].abs();
        if (v > vocalPeak) vocalPeak = v;
        if (ins > instPeak) instPeak = ins;
      }

      final vocalsWriter =
          await MonoWavWriter.create(vocalsOutPath, out.sampleRate);
      final instWriter =
          await MonoWavWriter.create(accompanimentOutPath, out.sampleRate);

      const batch = 44100 * 4;
      for (var offset = 0; offset < vocalsMono.length; offset += batch) {
        final len = math.min(batch, vocalsMono.length - offset);
        await vocalsWriter.writeFloat32Mono(
          vocalsMono,
          offset: offset,
          length: len,
        );
        await instWriter.writeFloat32Mono(
          instMono,
          offset: offset,
          length: len,
        );
      }

      await vocalsWriter.finalize();
      await instWriter.finalize();

      if (vocalPeak > 1e-9) {
        await scaleMonoWavInPlace(vocalsOutPath, 0.95 / vocalPeak);
      }
      if (instPeak > 1e-9) {
        await scaleMonoWavInPlace(accompanimentOutPath, 0.95 / instPeak);
      }

      if (kDebugMode) {
        debugPrint(
          '[Separation] native done — vocal peak=$vocalPeak inst peak=$instPeak len=${vocalsMono.length}',
        );
      }

      onProgress?.call(progressEnd);

      return SeparationFileResult(
        vocalsPath: vocalsOutPath,
        accompanimentPath: accompanimentOutPath,
        sampleRate: out.sampleRate,
        frameCount: vocalsMono.length,
      );
    } finally {
      if (output != null && output != nullptr) {
        bindings.destroyOutput(output);
      }
      calloc.free(leftNative);
      calloc.free(rightNative);
      calloc.free(channelPtrs);
    }
  }

  Float32List _stemToMono(Pointer<SherpaOnnxSourceSeparationStem> stemPtr) {
    final stem = stemPtr.ref;
    final n = stem.n;
    if (n <= 0 || stem.samples == nullptr) {
      return Float32List(0);
    }

    final channels = stem.num_channels;
    if (channels <= 0) {
      return Float32List(0);
    }

    final mono = Float32List(n);
    if (channels == 1) {
      final ch = stem.samples[0];
      if (ch == nullptr) {
        return mono;
      }
      mono.setAll(0, ch.asTypedList(n));
      return mono;
    }

    final ch0 = stem.samples[0];
    if (ch0 == nullptr) {
      return mono;
    }
    final first = ch0.asTypedList(n);
    mono.setAll(0, first);

    for (var c = 1; c < channels; c++) {
      final ch = stem.samples[c];
      if (ch == nullptr) {
        continue;
      }
      final data = ch.asTypedList(n);
      for (var i = 0; i < n; i++) {
        mono[i] += data[i];
      }
    }

    final scale = 1.0 / channels;
    for (var i = 0; i < n; i++) {
      mono[i] *= scale;
    }
    return mono;
  }

  Future<Pointer<SherpaOnnxOfflineSourceSeparation>> _ensureUvr({
    void Function(int progress)? onDownloadProgress,
  }) async {
    if (_uvrPtr != null && _uvrPtr != nullptr) {
      return _uvrPtr!;
    }

    final modelPath = await MlModelService.instance.ensureUvrMdxnet(
      onProgress: onDownloadProgress,
    );
    _uvrPtr = _createEngine(
      uvrModel: modelPath,
      spleeterVocals: '',
      spleeterAccompaniment: '',
    );
    return _uvrPtr!;
  }

  Future<Pointer<SherpaOnnxOfflineSourceSeparation>?> _tryEnsureSpleeter({
    void Function(int progress)? onDownloadProgress,
  }) async {
    if (_spleeterPtr != null && _spleeterPtr != nullptr) {
      return _spleeterPtr;
    }

    try {
      final paths = await MlModelService.instance.ensureSpleeterModels(
        onProgress: onDownloadProgress,
      );
      _spleeterPtr = _createEngine(
        uvrModel: '',
        spleeterVocals: paths.vocals,
        spleeterAccompaniment: paths.accompaniment,
      );
      return _spleeterPtr;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Separation] Spleeter models unavailable: $error');
      }
      return null;
    }
  }

  Pointer<SherpaOnnxOfflineSourceSeparation> _createEngine({
    required String uvrModel,
    required String spleeterVocals,
    required String spleeterAccompaniment,
  }) {
    final bindings = SherpaSourceSeparationBindings.instance;
    final config = calloc<SherpaOnnxOfflineSourceSeparationConfig>();

    config.ref.model.spleeter.vocals = spleeterVocals.toNativeUtf8();
    config.ref.model.spleeter.accompaniment =
        spleeterAccompaniment.toNativeUtf8();
    config.ref.model.uvr.model = uvrModel.toNativeUtf8();
    config.ref.model.numThreads = ProcessingConstants.uvrNativeNumThreads;
    config.ref.model.debug = 0;
    config.ref.model.provider = 'cpu'.toNativeUtf8();

    final ptr = bindings.create(config);

    calloc.free(config.ref.model.provider);
    calloc.free(config.ref.model.spleeter.vocals);
    calloc.free(config.ref.model.spleeter.accompaniment);
    calloc.free(config.ref.model.uvr.model);
    calloc.free(config);

    if (ptr == nullptr) {
      throw StateError('SherpaOnnxCreateOfflineSourceSeparation failed');
    }

    if (kDebugMode) {
      debugPrint(
        '[Separation] engine ready stems=${bindings.getNumStems(ptr)} '
        'sr=${bindings.getSampleRate(ptr)} threads=${ProcessingConstants.uvrNativeNumThreads}',
      );
    }

    return ptr;
  }
}
