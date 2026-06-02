import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/processing_constants.dart';
import '../models/separation_file_result.dart';
import 'ml_model_service.dart';
import 'sherpa_source_separation_bindings.dart';
import 'wav_stream_io.dart';

/// Fast on-device UVR MDX-NET 9482 via sherpa-onnx native C++ (Android primary).
///
/// Same model file as iOS [UvrSeparationService]. On Snapdragon devices uses
/// NNAPI so ONNX Runtime can offload to Qualcomm Hexagon NPU / DSP (Moises-style
/// native acceleration — no per-chunk Dart STFT loop).
class SherpaSourceSeparationService {
  SherpaSourceSeparationService._();

  static final SherpaSourceSeparationService instance =
      SherpaSourceSeparationService._();

  Pointer<SherpaOnnxOfflineSourceSeparation>? _uvrPtr;
  String? _activeProvider;
  int? _activeThreads;

  String get lastProvider => _activeProvider ?? 'cpu';

  Future<void> ensureReady({
    void Function(int downloadProgress)? onModelDownloadProgress,
    bool useSnapdragonAcceleration = false,
  }) async {
    SherpaSourceSeparationBindings.instance.ensureInitialized();
    final chain = useSnapdragonAcceleration
        ? ProcessingConstants.uvrSnapdragonProviderChain
        : ProcessingConstants.uvrAndroidProviderChain;
    await _ensureUvr(
      providerChain: chain,
      useSnapdragonAcceleration: useSnapdragonAcceleration,
      onDownloadProgress: onModelDownloadProgress,
    );
  }

  Future<SeparationFileResult> separateWavToFiles({
    required String wavPath,
    required String vocalsOutPath,
    required String accompanimentOutPath,
    void Function(int progress)? onProgress,
    void Function(int downloadProgress)? onModelDownloadProgress,
    bool useSnapdragonAcceleration = false,
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
      throw Exception('Expected stereo WAV for UVR separation.');
    }

    onProgress?.call(28);

    final chain = useSnapdragonAcceleration
        ? ProcessingConstants.uvrSnapdragonProviderChain
        : ProcessingConstants.uvrAndroidProviderChain;

    Object? lastError;
    for (final provider in chain) {
      try {
        final threads = _threadsFor(provider, useSnapdragonAcceleration);
        final uvr = await _ensureUvr(
          provider: provider,
          threads: threads,
          onDownloadProgress: onModelDownloadProgress,
        );

        if (kDebugMode) {
          debugPrint(
            '[Separation] native UVR MDX-NET 9482 provider=$provider '
            'threads=$threads frames=${info.frameCount}',
          );
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
        lastError = error;
        _disposeUvr();
        if (kDebugMode) {
          debugPrint('[Separation] provider=$provider failed: $error\n$stack');
        }
      }
    }

    throw StateError(
      'Native UVR MDX-NET failed (providers: ${chain.join(" → ")}): $lastError',
    );
  }

  int _threadsFor(String provider, bool snapdragon) {
    if (snapdragon && provider != 'cpu') {
      return ProcessingConstants.uvrSnapdragonNativeThreads;
    }
    return ProcessingConstants.uvrNativeNumThreads;
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
          '[Separation] native done provider=$lastProvider '
          'vocalPeak=$vocalPeak instPeak=$instPeak len=${vocalsMono.length}',
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
    String? provider,
    int? threads,
    List<String>? providerChain,
    bool useSnapdragonAcceleration = false,
    void Function(int progress)? onDownloadProgress,
  }) async {
    final resolvedProvider = provider ??
        (providerChain?.isNotEmpty == true ? providerChain!.first : 'cpu');
    final resolvedThreads = threads ??
        _threadsFor(resolvedProvider, useSnapdragonAcceleration);

    if (_uvrPtr != null &&
        _uvrPtr != nullptr &&
        _activeProvider == resolvedProvider &&
        _activeThreads == resolvedThreads) {
      return _uvrPtr!;
    }

    _disposeUvr();

    final modelPath = await MlModelService.instance.ensureUvrMdxnet(
      onProgress: onDownloadProgress,
    );

    _uvrPtr = _createEngine(
      uvrModel: modelPath,
      provider: resolvedProvider,
      threads: resolvedThreads,
    );
    _activeProvider = resolvedProvider;
    _activeThreads = resolvedThreads;
    return _uvrPtr!;
  }

  void _disposeUvr() {
    if (_uvrPtr == null || _uvrPtr == nullptr) {
      return;
    }
    SherpaSourceSeparationBindings.instance.destroy(_uvrPtr!);
    _uvrPtr = null;
    _activeProvider = null;
    _activeThreads = null;
  }

  Pointer<SherpaOnnxOfflineSourceSeparation> _createEngine({
    required String uvrModel,
    required String provider,
    required int threads,
  }) {
    final bindings = SherpaSourceSeparationBindings.instance;
    final config = calloc<SherpaOnnxOfflineSourceSeparationConfig>();

    config.ref.model.spleeter.vocals = ''.toNativeUtf8();
    config.ref.model.spleeter.accompaniment = ''.toNativeUtf8();
    config.ref.model.uvr.model = uvrModel.toNativeUtf8();
    config.ref.model.numThreads = threads;
    config.ref.model.debug = kDebugMode ? 1 : 0;
    config.ref.model.provider = provider.toNativeUtf8();

    final ptr = bindings.create(config);

    calloc.free(config.ref.model.provider);
    calloc.free(config.ref.model.spleeter.vocals);
    calloc.free(config.ref.model.spleeter.accompaniment);
    calloc.free(config.ref.model.uvr.model);
    calloc.free(config);

    if (ptr == nullptr) {
      throw StateError(
        'SherpaOnnxCreateOfflineSourceSeparation failed (provider=$provider)',
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[Separation] engine ready model=UVR_MDXNET_9482 provider=$provider '
        'threads=$threads stems=${bindings.getNumStems(ptr)} '
        'sr=${bindings.getSampleRate(ptr)}',
      );
    }

    return ptr;
  }
}
