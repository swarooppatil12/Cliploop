import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/processing_constants.dart';
import '../core/utils/file_helper.dart';
import '../models/segment.dart';
import '../models/stem_pair_result.dart';
import '../models/separation_file_result.dart';
import '../models/separation_result.dart';
import '../models/track_stem.dart';
import '../models/vocal_model_output.dart';
import '../models/whisper_result.dart';
import 'gapless_mix_service.dart';
import 'uvr_separation_service.dart';
import 'silero_vad_service.dart';
import 'vocal_separation_engine.dart';
import 'vocal_silence_service.dart';
import 'wav_stream_io.dart';

/// On-device audio decode, UVR MDX-NET separation, vocal detection, and structure
/// analysis. Song processing stays on the phone — models download once, then
/// run locally (no cloud separation).
class LocalAudioEngine {
  LocalAudioEngine({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  Future<SeparationResult> runSpleeter({
    required String inputPath,
    required String model,
    required String musicFileId,
    void Function(int progress)? onProgress,
  }) async {
    final scanStopwatch = Stopwatch()..start();
    var mlSeparationElapsed = Duration.zero;
    var svadAndStructureElapsed = Duration.zero;

    onProgress?.call(5);

    await _ensureSeparationReady(
      onModelDownloadProgress: (p) => onProgress?.call(5 + (p * 10 ~/ 100)),
    );
    onProgress?.call(15);

    final wav = await _ensureWavOnDisk(inputPath);
    onProgress?.call(22);

    try {
    final jobId = _uuid.v4();
    final stemDir = await _stemOutputDirectory(jobId);
    final vocalsPath = FileHelper.joinPath(stemDir.path, 'vocals.wav');
    final instPath = FileHelper.joinPath(stemDir.path, 'accompaniment.wav');

    final sepStopwatch = Stopwatch()..start();
    final sepResult = await _separateWavToFiles(
      wavPath: wav.path,
      vocalsOutPath: vocalsPath,
      accompanimentOutPath: instPath,
      onProgress: onProgress,
    );
    mlSeparationElapsed = sepStopwatch.elapsed;
    onProgress?.call(78);

    final stems = <TrackStem>[];
    final stemTimestamps = <Segment>[];

    for (final entry in <String, String>{
      'vocals': vocalsPath,
      'accompaniment': instPath,
    }.entries) {
      stems.add(
        TrackStem(
          id: entry.key,
          type: _stemType(entry.key),
          audioPath: entry.value,
          durationSeconds: sepResult.durationSeconds,
          waveformData: await _generateWaveformFromPath(entry.value),
        ),
      );
    }

    final vocalMono = await loadMonoFromWav(vocalsPath);
    stemTimestamps.addAll(
      _detectActiveRegions(vocalMono, sepResult.sampleRate, 'vocals'),
    );

    onProgress?.call(75);

    final vocalStem = StemPcm(samples: vocalMono, mono: vocalMono);
    final VocalModelOutput? vocalModelOutput;
    final List<Segment> structureSegments;

    if (vocalMono.isEmpty) {
      vocalModelOutput = null;
      structureSegments = const [];
    } else {
      final durationSeconds = sepResult.durationSeconds;

      onProgress?.call(80);
      final svadStopwatch = Stopwatch()..start();
      var vadStem = await SileroVadService.instance.detectVocalRegions(
        mono: vocalMono,
        sourceSampleRate: sepResult.sampleRate,
        onModelDownloadProgress: (p) => onProgress?.call(80 + (p * 6 ~/ 100)),
      );
      onProgress?.call(88);

      final drumsStem = await _drumsStemForStructure(
        mixWavPath: wav.path,
        vocalMono: vocalMono,
        separatedInstPath: instPath,
      );
      final energyRegions = _detectVocalRegionsOnStem(
        vocalMono,
        sepResult.sampleRate,
        drumsStem: drumsStem,
      );
      final vadCoverage = SileroVadService.coverageFraction(
        vadStem,
        durationSeconds,
      );
      final energyCoverage = SileroVadService.coverageFraction(
        energyRegions,
        durationSeconds,
      );

      final List<(double, double)> vocalRegionsOverride;
      if (vadCoverage < ProcessingConstants.minVadCoverageFraction) {
        vocalRegionsOverride = energyRegions;
      } else if (energyCoverage >
              vadCoverage * ProcessingConstants.vadEnergyMergeMaxRatio &&
          energyRegions.isNotEmpty) {
        vocalRegionsOverride = _mergeVocalDetections(
          vadRegions: vadStem,
          energyRegions: energyRegions,
          vocalStem: vocalMono,
          drumsStem: drumsStem,
          sampleRate: sepResult.sampleRate,
        );
      } else {
        vocalRegionsOverride = vadStem;
      }

      stemTimestamps.addAll(
        _detectActiveRegions(drumsStem, sepResult.sampleRate, 'accompaniment'),
      );

      final pipeline = _runStructurePipeline(
        vocalStem,
        sepResult.sampleRate,
        methodLabel: 'Method 1 (UVR)',
        stemModel: model,
        drumsStem: drumsStem,
        vocalRegionsOverride: vocalRegionsOverride,
      );
      structureSegments = pipeline.structureSegments;
      vocalModelOutput = pipeline.vocalModelOutput;
      _logVocalModelOutput(vocalModelOutput.rawLog);
      svadAndStructureElapsed = svadStopwatch.elapsed;
    }

    onProgress?.call(95);

    _logScanTimingComplete(
      methodLabel: 'Method 1 (UVR ML + SVAD)',
      total: scanStopwatch.elapsed,
      mlSeparation: mlSeparationElapsed,
      svadAndStructure: svadAndStructureElapsed,
    );

    return SeparationResult(
      musicFileId: musicFileId,
      stems: stems,
      stemTimestamps: stemTimestamps,
      structureSegments: structureSegments,
      vocalModelOutput: vocalModelOutput,
      processedAt: DateTime.now(),
      model: _activeSeparationModelId(),
    );
    } finally {
      await _deleteTempWavIfNeeded(wav);
    }
  }

  Future<WhisperResult> runWhisper({
    required String inputPath,
    required String musicFileId,
    void Function(int progress)? onProgress,
  }) async {
    final scanStopwatch = Stopwatch()..start();
    var mlSeparationElapsed = Duration.zero;
    var svadAndStructureElapsed = Duration.zero;

    onProgress?.call(5);

    // Decode first, then load the UVR MDX-NET separation model.
    onProgress?.call(8);
    final wav = await _ensureWavOnDisk(inputPath);
    onProgress?.call(18);

    await _ensureSeparationReady(
      onModelDownloadProgress: (p) => onProgress?.call(18 + (p * 8 ~/ 100)),
    );
    onProgress?.call(22);

    try {
    final jobId = _uuid.v4();
    final stemDir = await _stemOutputDirectory(jobId);
    final vocalsPath = FileHelper.joinPath(stemDir.path, 'vocals.wav');
    final instPath = FileHelper.joinPath(stemDir.path, 'accompaniment.wav');

    final sepStopwatch = Stopwatch()..start();
    final sepResult = await _separateWavToFiles(
      wavPath: wav.path,
      vocalsOutPath: vocalsPath,
      accompanimentOutPath: instPath,
      onProgress: onProgress,
    );
    mlSeparationElapsed = sepStopwatch.elapsed;
    onProgress?.call(68);

    if (kDebugMode) {
      debugPrint('[Whisper] separation complete');
      debugPrint('[Whisper] vocals.wav → $vocalsPath');
      debugPrint('[Whisper] accompaniment.wav → $instPath');
    }

    final stems = <TrackStem>[];
    for (final entry in <String, String>{
      'vocals': vocalsPath,
      'accompaniment': instPath,
    }.entries) {
      stems.add(
        TrackStem(
          id: entry.key,
          type: _stemType(entry.key),
          audioPath: entry.value,
          durationSeconds: sepResult.durationSeconds,
          waveformData: await _generateWaveformFromPath(entry.value),
        ),
      );
    }

    onProgress?.call(75);

    final vocalMono = await loadMonoFromWav(vocalsPath);
    final vocalStem = StemPcm(samples: vocalMono, mono: vocalMono);
    final VocalModelOutput? vocalModelOutput;
    final List<Segment> structureSegments;

    if (vocalMono.isEmpty) {
      vocalModelOutput = null;
      structureSegments = const [];
    } else {
      final durationSeconds = sepResult.durationSeconds;

      onProgress?.call(80);
      final svadStopwatch = Stopwatch()..start();
      var vadStem = await SileroVadService.instance.detectVocalRegions(
        mono: vocalMono,
        sourceSampleRate: sepResult.sampleRate,
        onModelDownloadProgress: (p) => onProgress?.call(80 + (p * 6 ~/ 100)),
      );
      onProgress?.call(88);

      final drumsStem = await _drumsStemForStructure(
        mixWavPath: wav.path,
        vocalMono: vocalMono,
        separatedInstPath: instPath,
      );
      final energyRegions = _detectVocalRegionsOnStem(
        vocalMono,
        sepResult.sampleRate,
        drumsStem: drumsStem,
      );
      final vadCoverage = SileroVadService.coverageFraction(
        vadStem,
        durationSeconds,
      );
      final energyCoverage = SileroVadService.coverageFraction(
        energyRegions,
        durationSeconds,
      );

      List<(double, double)> vocalRegionsOverride;
      if (vadCoverage < ProcessingConstants.minVadCoverageFraction) {
        vocalRegionsOverride = energyRegions;
      } else if (energyCoverage >
              vadCoverage * ProcessingConstants.vadEnergyMergeMaxRatio &&
          energyRegions.isNotEmpty) {
        vocalRegionsOverride = _mergeVocalDetections(
          vadRegions: vadStem,
          energyRegions: energyRegions,
          vocalStem: vocalMono,
          drumsStem: drumsStem,
          sampleRate: sepResult.sampleRate,
        );
      } else {
        vocalRegionsOverride = vadStem;
      }

      final pipeline = _runStructurePipeline(
        vocalStem,
        sepResult.sampleRate,
        methodLabel: 'Method 2 (Vocal Remover · SVAD)',
        stemModel: ProcessingConstants.svadModelLabel,
        drumsStem: drumsStem,
        vocalRegionsOverride: vocalRegionsOverride,
      );
      structureSegments = pipeline.structureSegments;
      vocalModelOutput = pipeline.vocalModelOutput;
      _logVocalModelOutput(vocalModelOutput.rawLog);
      svadAndStructureElapsed = svadStopwatch.elapsed;
    }

    onProgress?.call(95);

    _logScanTimingComplete(
      methodLabel: 'Method 2 (Vocal Remover ML + SVAD)',
      total: scanStopwatch.elapsed,
      mlSeparation: mlSeparationElapsed,
      svadAndStructure: svadAndStructureElapsed,
    );

    return WhisperResult(
      musicFileId: musicFileId,
      stems: stems,
      segments: structureSegments,
      vocalTimestamps: vocalModelOutput?.vocalTimestamps ?? const [],
      nonVocalSegments: vocalModelOutput?.nonVocalPartSegments ?? const [],
      vocalModelOutput: vocalModelOutput,
      vocalSeparationModel: ProcessingConstants.svadModelLabel,
      separationModel: _activeSeparationModelId(),
      processedAt: DateTime.now(),
    );
    } finally {
      await _deleteTempWavIfNeeded(wav);
    }
  }

  /// Method 3 — analyze pre-separated vocal + instrumental stems (no ML separation).
  Future<StemPairResult> analyzeStemPair({
    required String vocalPath,
    required String bgmPath,
    required String vocalFileName,
    required String bgmFileName,
  }) async {
    final vocalPcm = await _loadPcm(vocalPath);
    final bgmPcm = await _loadPcm(bgmPath);

    var vocal = Float32List.fromList(vocalPcm.mono);
    var bgm = Float32List.fromList(bgmPcm.mono);
    var sampleRate = vocalPcm.sampleRate;
    final warnings = <String>[];

    if (bgmPcm.sampleRate != sampleRate) {
      bgm = _resampleMono(bgm, bgmPcm.sampleRate, sampleRate);
      warnings.add(
        'Instrumental resampled from ${bgmPcm.sampleRate} Hz → $sampleRate Hz to match vocal.',
      );
    }

    final minLen = math.min(vocal.length, bgm.length);
    if (vocal.length != bgm.length) {
      final vocalDur = vocal.length / sampleRate;
      final bgmDur = bgm.length / sampleRate;
      warnings.add(
        'Length mismatch: vocal ${vocalDur.toStringAsFixed(1)}s, '
        'instrumental ${bgmDur.toStringAsFixed(1)}s — '
        'analyzing first ${(minLen / sampleRate).toStringAsFixed(1)}s.',
      );
      vocal = Float32List.sublistView(vocal, 0, minLen);
      bgm = Float32List.sublistView(bgm, 0, minLen);
    }

    final duration = minLen / sampleRate;
    final vocalStem = StemPcm(samples: vocal, mono: vocal);
    final vocalSilence = VocalSilenceService.analyze(vocal, sampleRate, duration);

    final pipeline = _runStructurePipeline(
      vocalStem,
      sampleRate,
      methodLabel: 'Stem pair analysis',
      stemModel: 'uploaded vocal + BGM',
      drumsStem: bgm,
    );

    final tempDir = await getTemporaryDirectory();
    final jobId = _uuid.v4();
    final vocalStemPath = FileHelper.joinPath(tempDir.path, 'm3_vocal_$jobId.wav');
    final bgmStemPath = FileHelper.joinPath(tempDir.path, 'm3_bgm_$jobId.wav');
    await _writeWav(vocalStemPath, vocalStem, sampleRate);
    await _writeWav(bgmStemPath, StemPcm(samples: bgm, mono: bgm), sampleRate);

    return StemPairResult(
      vocalFileName: vocalFileName,
      bgmFileName: bgmFileName,
      vocalStemPath: vocalStemPath,
      bgmStemPath: bgmStemPath,
      sampleRate: sampleRate,
      durationSeconds: duration,
      warnings: warnings,
      structureSegments: pipeline.structureSegments,
      vocalModelOutput: pipeline.vocalModelOutput,
      vocalSilence: vocalSilence,
      vocalWaveform: _generateWaveform(vocal),
      bgmWaveform: _generateWaveform(bgm),
      processedAt: DateTime.now(),
    );
  }

  Float32List _resampleMono(Float32List input, int fromRate, int toRate) {
    if (fromRate == toRate || input.isEmpty) {
      return input;
    }
    final ratio = fromRate / toRate;
    final outLength = (input.length / ratio).floor();
    if (outLength <= 0) {
      return Float32List(0);
    }
    final output = Float32List(outLength);
    for (var i = 0; i < outLength; i++) {
      final srcPos = i * ratio;
      final index = srcPos.floor();
      final frac = srcPos - index;
      final a = input[index.clamp(0, input.length - 1)];
      final b = input[math.min(index + 1, input.length - 1)];
      output[i] = a * (1 - frac) + b * frac;
    }
    return output;
  }

  /// Combines vocal + drums stems, removes interludes with crossfade, writes WAV.
  Future<GaplessMixExport> exportGaplessMixWav({
    required String inputPath,
    required List<Segment> structureSegments,
    String? vocalsStemPath,
    String? drumsStemPath,
    String vocalModel = ProcessingConstants.defaultMethod2VocalModel,
    int crossfadeMs = GaplessMixService.defaultCrossfadeMs,
  }) async {
    late final Float32List vocals;
    late final Float32List? drums;
    late final int sampleRate;
    late final double duration;

    if (vocalsStemPath != null && vocalsStemPath.isNotEmpty) {
      final vocalPcm = await _loadPcm(vocalsStemPath);
      vocals = vocalPcm.mono;
      sampleRate = vocalPcm.sampleRate;
      duration = vocalPcm.durationSeconds;
      if (drumsStemPath != null && drumsStemPath.isNotEmpty) {
        final drumPcm = await _loadPcm(drumsStemPath);
        drums = drumPcm.mono;
      } else {
        drums = null;
      }
    } else {
      final pcm = await _loadPcm(inputPath);
      sampleRate = pcm.sampleRate;
      duration = pcm.durationSeconds;
      final stems = VocalSeparationEngine.separate(
        left: pcm.left,
        right: pcm.right,
        model: vocalModel,
      );
      vocals = stems.vocals;
      drums = stems.drums;
    }

    final mix = GaplessMixService.buildGaplessMix(
      vocals: vocals,
      drums: drums,
      sampleRate: sampleRate,
      duration: duration,
      structureSegments: structureSegments,
      crossfadeMs: crossfadeMs,
    );

    final tempDir = await getTemporaryDirectory();
    final outputPath = FileHelper.joinPath(
      tempDir.path,
      'gapless_${_uuid.v4()}.wav',
    );
    await GaplessMixService.writeWav(
      outputPath: outputPath,
      samples: mix.samples,
      sampleRate: sampleRate,
    );

    return GaplessMixExport(
      wavPath: outputPath,
      result: mix,
    );
  }

  String _activeSeparationModelId() {
    return ProcessingConstants.mobileSeparationModelId;
  }

  Future<void> _ensureSeparationReady({
    void Function(int downloadProgress)? onModelDownloadProgress,
  }) async {
    await UvrSeparationService.instance.ensureReady(
      onModelDownloadProgress: onModelDownloadProgress,
    );
  }

  Future<SeparationFileResult> _separateWavToFiles({
    required String wavPath,
    required String vocalsOutPath,
    required String accompanimentOutPath,
    void Function(int progress)? onProgress,
  }) {
    return UvrSeparationService.instance.separateWavToFiles(
      wavPath: wavPath,
      vocalsOutPath: vocalsOutPath,
      accompanimentOutPath: accompanimentOutPath,
      onProgress: onProgress,
    );
  }

  /// Decodes to a 44.1 kHz stereo WAV path without loading PCM into memory.
  Future<({String path, bool isTemporary})> _ensureWavOnDisk(
    String inputPath,
  ) async {
    final extension = FileHelper.fileExtension(inputPath).toLowerCase();
    if (extension == 'wav') {
      return (path: inputPath, isTemporary: false);
    }

    final tempDir = await getTemporaryDirectory();
    final wavPath = FileHelper.joinPath(
      tempDir.path,
      'cliploops_${_uuid.v4()}.wav',
    );

    // Force 16-bit PCM: the separation WAV reader only supports pcm_s16le.
    final command =
        '-y -i "$inputPath" -ac 2 -ar ${ProcessingConstants.defaultSampleRate} -c:a pcm_s16le "$wavPath"';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception(
        'Could not decode audio on device. ${logs ?? 'FFmpeg failed.'}',
      );
    }

    return (path: wavPath, isTemporary: true);
  }

  Future<void> _deleteTempWavIfNeeded(({String path, bool isTemporary}) wav) async {
    if (!wav.isTemporary) {
      return;
    }
    final file = File(wav.path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<List<double>> _generateWaveformFromPath(String audioPath) async {
    final source = File(audioPath);
    if (!await source.exists()) {
      return List<double>.filled(AppConstants.waveformSampleCount, 0);
    }

    final controller = PlayerController();
    try {
      final waveform = await controller.extractWaveformData(
        path: audioPath,
        noOfSamples: AppConstants.waveformSampleCount,
      );
      if (waveform.isEmpty) {
        return List<double>.filled(AppConstants.waveformSampleCount, 0);
      }
      return waveform.map((value) => value.clamp(0.0, 1.0)).toList();
    } catch (_) {
      return List<double>.filled(AppConstants.waveformSampleCount, 0);
    } finally {
      controller.dispose();
    }
  }

  Future<PcmAudio> _loadPcm(String inputPath, {bool includeMono = true}) async {
    final extension = FileHelper.fileExtension(inputPath).toLowerCase();
    if (extension == 'wav') {
      return _readWav(File(inputPath), includeMono: includeMono);
    }

    final tempDir = await getTemporaryDirectory();
    final wavPath = FileHelper.joinPath(
      tempDir.path,
      'cliploops_${_uuid.v4()}.wav',
    );

    // Force 16-bit PCM: the separation WAV reader only supports pcm_s16le.
    final command =
        '-y -i "$inputPath" -ac 2 -ar ${ProcessingConstants.defaultSampleRate} -c:a pcm_s16le "$wavPath"';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception(
        'Could not decode audio on device. ${logs ?? 'FFmpeg failed.'}',
      );
    }

    try {
      return await _readWav(File(wavPath), includeMono: includeMono);
    } finally {
      final temp = File(wavPath);
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  Future<PcmAudio> _readWav(File file, {bool includeMono = true}) async {
    final raf = await file.open();
    try {
      final fileLength = await raf.length();
      if (fileLength < 44) {
        throw Exception('Invalid WAV file: ${file.path}');
      }

      var offset = 12;
      var sampleRate = ProcessingConstants.defaultSampleRate;
      var channels = 2;
      var bitsPerSample = 16;
      var dataOffset = -1;
      var dataSize = 0;

      while (offset + 8 <= fileLength) {
        await raf.setPosition(offset);
        final chunkHeader = await raf.read(8);
        if (chunkHeader.length < 8) {
          break;
        }

        final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
        final chunkSize =
            ByteData.sublistView(chunkHeader).getUint32(4, Endian.little);
        final chunkDataOffset = offset + 8;

        if (chunkId == 'fmt ') {
          final fmt = await raf.read(math.min(chunkSize, 16));
          if (fmt.length >= 16) {
            final fmtData = ByteData.sublistView(fmt);
            channels = fmtData.getUint16(2, Endian.little);
            sampleRate = fmtData.getUint32(4, Endian.little);
            bitsPerSample = fmtData.getUint16(14, Endian.little);
          }
        } else if (chunkId == 'data') {
          dataOffset = chunkDataOffset;
          dataSize = chunkSize;
          break;
        }

        offset = chunkDataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
      }

      if (dataOffset < 0) {
        throw Exception('WAV data chunk not found: ${file.path}');
      }

      if (bitsPerSample != 16) {
        throw Exception('Only 16-bit WAV is supported after decode.');
      }

      if (dataSize <= 0) {
        dataSize = fileLength - dataOffset;
      }

      await raf.setPosition(dataOffset);

      final frameCount = dataSize ~/ (channels * 2);
      final left = Float32List(frameCount);
      final right = Float32List(frameCount);
      final mono = includeMono ? Float32List(frameCount) : Float32List(0);

      const batchFrames = 8192;
      var frame = 0;
      while (frame < frameCount) {
        final batch = math.min(batchFrames, frameCount - frame);
        final byteCount = batch * channels * 2;
        final chunk = await raf.read(byteCount);
        if (chunk.isEmpty) {
          break;
        }

        final chunkData = ByteData.sublistView(chunk);
        final framesInChunk = chunk.length ~/ (channels * 2);
        for (var i = 0; i < framesInChunk; i++) {
          final index = i * channels * 2;
          final l = chunkData.getInt16(index, Endian.little) / 32768.0;
          final r = channels > 1
              ? chunkData.getInt16(index + 2, Endian.little) / 32768.0
              : l;
          final out = frame + i;
          if (out >= frameCount) {
            break;
          }
          left[out] = l;
          right[out] = r;
          if (includeMono) {
            mono[out] = (l + r) * 0.5;
          }
        }
        frame += framesInChunk;
      }

      return PcmAudio(
        mono: mono,
        left: left,
        right: right,
        sampleRate: sampleRate,
      );
    } finally {
      await raf.close();
    }
  }

  Future<void> _writeWav(
    String path,
    StemPcm stem,
    int sampleRate,
  ) async {
    final samples = stem.samples;
    final buffer = BytesBuilder();
    final dataSize = samples.length * 2;
    final fileSize = 36 + dataSize;

    buffer.add('RIFF'.codeUnits);
    buffer.add(_int32Le(fileSize));
    buffer.add('WAVE'.codeUnits);
    buffer.add('fmt '.codeUnits);
    buffer.add(_int32Le(16));
    buffer.add(_int16Le(1));
    buffer.add(_int16Le(1));
    buffer.add(_int32Le(sampleRate));
    buffer.add(_int32Le(sampleRate * 2));
    buffer.add(_int16Le(2));
    buffer.add(_int16Le(16));
    buffer.add('data'.codeUnits);
    buffer.add(_int32Le(dataSize));

    for (final sample in samples) {
      final clamped = sample.clamp(-1.0, 1.0);
      buffer.add(_int16Le((clamped * 32767).round()));
    }

    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(buffer.toBytes(), flush: true);
  }

  List<double> _generateWaveform(Float32List samples, {int points = 120}) {
    if (samples.isEmpty) {
      return List<double>.filled(points, 0);
    }

    final bucket = math.max(1, samples.length ~/ points);
    final waveform = <double>[];

    for (var index = 0; index < samples.length; index += bucket) {
      final end = math.min(index + bucket, samples.length);
      var peak = 0.0;
      for (var i = index; i < end; i++) {
        peak = math.max(peak, samples[i].abs());
      }
      waveform.add(peak.clamp(0.0, 1.0));
    }

    while (waveform.length < points) {
      waveform.add(0.0);
    }
    return waveform.take(points).toList();
  }

  List<Segment> _detectActiveRegions(
    Float32List samples,
    int sampleRate,
    String label,
  ) {
    if (samples.isEmpty) {
      return [];
    }

    const frameLength = 2048;
    const hopLength = 512;
    final rms = <double>[];
    final times = <double>[];

    for (var start = 0; start + frameLength <= samples.length; start += hopLength) {
      var sum = 0.0;
      for (var i = start; i < start + frameLength; i++) {
        sum += samples[i] * samples[i];
      }
      rms.add(math.sqrt(sum / frameLength));
      times.add(start / sampleRate);
    }

    if (rms.isEmpty) {
      return [];
    }

    final sorted = List<double>.from(rms)..sort();
    final threshold = sorted[(sorted.length * 0.7).floor()];

    final regions = <Segment>[];
    int? startIndex;

    for (var index = 0; index < rms.length; index++) {
      final isActive = rms[index] >= threshold;
      if (isActive && startIndex == null) {
        startIndex = index;
      } else if (!isActive && startIndex != null) {
        regions.add(_timestampSegment(
          label,
          times[startIndex],
          times[index > 0 ? index - 1 : index],
          _mean(rms, startIndex, index),
        ));
        startIndex = null;
      }
    }

    if (startIndex != null) {
      regions.add(_timestampSegment(
        label,
        times[startIndex],
        times.last,
        _mean(rms, startIndex, rms.length),
      ));
    }

    return regions;
  }

  double _mean(List<double> values, int start, int end) {
    if (end <= start) {
      return 0;
    }
    var sum = 0.0;
    for (var i = start; i < end; i++) {
      sum += values[i];
    }
    return sum / (end - start);
  }

  Segment _timestampSegment(
    String label,
    double start,
    double end,
    double meanRms,
  ) {
    if (end <= start) {
      end = start + 0.25;
    }
    final confidence = meanRms * 4;
    return Segment(
      id: '${label}_${start.toStringAsFixed(2)}_${end.toStringAsFixed(2)}',
      type: SegmentType.unknown,
      startSeconds: _round3(start),
      endSeconds: _round3(end),
      hasVocals: label == 'vocals',
      confidence: confidence.clamp(0.4, 0.99),
      label: '$label active',
    );
  }

  /// 1 Vocals → 2 Non-vocal opposite → 3 Parts → 4 Prelude / Interlude / Postlude.
  _StructurePipelineResult _runStructurePipeline(
    StemPcm vocalStem,
    int sampleRate, {
    required String methodLabel,
    String? stemModel,
    Float32List? drumsStem,
    List<(double, double)>? vocalRegionsOverride,
  }) {
    final duration = vocalStem.mono.length / sampleRate;

    // Step 1 — vocal regions (ML VAD override or stem energy + instrumental ratio).
    final vocalRegions = vocalRegionsOverride ??
        _detectVocalRegionsOnStem(
          vocalStem.mono,
          sampleRate,
          drumsStem: drumsStem,
        );

    // Step 2 — opposite: everything that is not vocal.
    final nonVocalOpposite = _mergeRegions(
      _invertRegions(vocalRegions, duration),
      gap: 0.35,
    );

    // Step 3 — distinct non-vocal parts (min duration filter).
    final nonVocalParts = _filterRegionsByMinDuration(
      nonVocalOpposite,
      ProcessingConstants.minStructureGapSeconds,
    );

    final vocalTimestamps =
        _regionsToSegments(vocalRegions, hasVocals: true, label: 'vocal');
    final nonVocalOppositeSegments = _partsToSegments(
      nonVocalOpposite,
      vocalStem.mono,
      sampleRate,
      labelPrefix: 'non-vocal',
    );
    final nonVocalPartSegments = _partsToSegments(
      nonVocalParts,
      vocalStem.mono,
      sampleRate,
      labelPrefix: 'part',
    );

    // Step 4 — structure blocks (merged vocals) → Prelude / Interlude / Postlude.
    final structureBlocks = _buildStructureVocalBlocks(vocalRegions);
    final preludeEnd = _findPreludeEndSeconds(
      vocalRegions,
      vocalStem: vocalStem.mono,
      drumsStem: drumsStem,
      sampleRate: sampleRate,
    );
    final mainVocalEnd = structureBlocks.isEmpty
        ? duration
        : _findPostludeStartSeconds(structureBlocks, vocalRegions, duration);
    final structureSegments = _finalizeStructureSegments(
      markers: _mapStructureBlocksToMarkers(
        duration: duration,
        structureBlocks: structureBlocks,
        rawVocalRegions: vocalRegions,
        vocalStem: vocalStem.mono,
        drumsStem: drumsStem,
        sampleRate: sampleRate,
        nonVocalParts: nonVocalParts,
      ),
      vocalStem: vocalStem.mono,
      drumsStem: drumsStem,
      sampleRate: sampleRate,
      duration: duration,
      vocalRegions: vocalRegions,
      preludeEnd: preludeEnd,
      mainVocalEnd: mainVocalEnd,
      structureBlocks: structureBlocks,
    );

    final mainEndForLog = structureBlocks.isEmpty
        ? duration
        : _findPostludeStartSeconds(structureBlocks, vocalRegions, duration);
    final interludeCandidatesForLog = _finalizeInterludeGaps(
      nonVocalParts: nonVocalParts,
      rawVocalRegions: vocalRegions,
      structureBlocks: structureBlocks,
      preludeEnd: preludeEnd,
      mainVocalEnd: mainEndForLog,
      vocalStem: vocalStem.mono,
      drumsStem: drumsStem,
      sampleRate: sampleRate,
    );

    final analysis = _PipelineAnalysis(
      vocalRegions: vocalRegions,
      structureBlocks: structureBlocks,
      preludeEnd: preludeEnd,
      interludeCandidates: interludeCandidatesForLog,
      nonVocalOpposite: nonVocalOpposite,
      nonVocalParts: nonVocalParts,
    );

    final vocalModelOutput = _buildVocalModelOutput(
      method: methodLabel,
      model: stemModel,
      duration: duration,
      sampleRate: sampleRate,
      analysis: analysis,
      vocalTimestamps: vocalTimestamps,
      nonVocalOppositeSegments: nonVocalOppositeSegments,
      nonVocalPartSegments: nonVocalPartSegments,
      structureSegments: structureSegments,
    );

    return _StructurePipelineResult(
      structureSegments: structureSegments,
      vocalModelOutput: vocalModelOutput,
    );
  }

  /// Step 1 — vocal regions on the isolated vocals stem (adaptive RMS + optional ratio gate).
  List<(double, double)> _detectVocalRegionsOnStem(
    Float32List samples,
    int sampleRate, {
    Float32List? drumsStem,
  }) {
    if (samples.isEmpty) {
      return [];
    }

    const frameLength = 2048;
    const hopLength = 512;
    final rmsValues = <double>[];
    final musicRmsValues = <double>[];
    final frameStarts = <double>[];
    final frameEnds = <double>[];

    for (var start = 0; start + frameLength <= samples.length; start += hopLength) {
      var sum = 0.0;
      for (var i = start; i < start + frameLength; i++) {
        sum += samples[i] * samples[i];
      }
      rmsValues.add(math.sqrt(sum / frameLength));
      frameStarts.add(start / sampleRate);
      frameEnds.add((start + frameLength) / sampleRate);

      if (drumsStem != null) {
        var musicSum = 0.0;
        for (var i = start; i < start + frameLength; i++) {
          if (i < drumsStem.length) {
            musicSum += drumsStem[i] * drumsStem[i];
          }
        }
        musicRmsValues.add(math.sqrt(musicSum / frameLength));
      }
    }

    if (rmsValues.isEmpty) {
      return [];
    }

    final sorted = List<double>.from(rmsValues)..sort();
    final quietIndex =
        (sorted.length * 0.20).floor().clamp(0, sorted.length - 1);
    final midIndex =
        (sorted.length * 0.50).floor().clamp(0, sorted.length - 1);
    final quietRef = sorted[quietIndex];
    final midRef = sorted[midIndex];

    final adaptive = quietRef +
        (midRef - quietRef) * ProcessingConstants.vocalStemAdaptiveBlend;
    final onThreshold = math.max(
      ProcessingConstants.vocalStemPresentThreshold,
      adaptive,
    );
    final offThreshold =
        onThreshold * ProcessingConstants.vocalStemHysteresisRatio;

    final minVocalSeconds = ProcessingConstants.minVocalRegionSeconds;
    final regions = <(double, double)>[];
    var inVocal = false;
    int? activeStart;
    var vocalRun = 0;
    var silentRun = 0;

    for (var index = 0; index < rmsValues.length; index++) {
      final musicRms = drumsStem != null && index < musicRmsValues.length
          ? musicRmsValues[index]
          : 0.0;
      final threshold = inVocal ? offThreshold : onThreshold;
      final isVocalFrame = _isVocalFrame(
        vocalRms: rmsValues[index],
        musicRms: musicRms,
        threshold: threshold,
      );

      if (isVocalFrame) {
        vocalRun++;
        silentRun = 0;
        if (!inVocal &&
            vocalRun >= ProcessingConstants.vocalOnsetMinFrames &&
            activeStart == null) {
          activeStart = index - vocalRun + 1;
          inVocal = true;
        }
      } else {
        silentRun++;
        vocalRun = 0;
        if (inVocal &&
            silentRun >= ProcessingConstants.vocalOffsetMinFrames &&
            activeStart != null) {
          final startSeconds = frameStarts[activeStart];
          final endSeconds = frameEnds[index - silentRun];
          if (endSeconds - startSeconds >= minVocalSeconds) {
            regions.add((startSeconds, endSeconds));
          }
          activeStart = null;
          inVocal = false;
        }
      }
    }

    if (activeStart != null) {
      final startSeconds = frameStarts[activeStart];
      final endSeconds = frameEnds.last;
      if (endSeconds - startSeconds >= minVocalSeconds) {
        regions.add((startSeconds, endSeconds));
      }
    }

    return _mergeRegions(
      regions,
      gap: ProcessingConstants.vocalRegionMergeGapSeconds,
    );
  }

  bool _isVocalFrame({
    required double vocalRms,
    required double musicRms,
    required double threshold,
  }) {
    if (vocalRms < threshold) {
      return false;
    }
    if (musicRms <= 0) {
      return true;
    }
    return vocalRms / math.max(musicRms, 1e-9) >=
        ProcessingConstants.vocalToInstrumentalMinRatio;
  }

  List<(double, double)> _mergeVocalDetections({
    required List<(double, double)> vadRegions,
    required List<(double, double)> energyRegions,
    required Float32List vocalStem,
    Float32List? drumsStem,
    required int sampleRate,
  }) {
    final merged = List<(double, double)>.from(vadRegions);

    for (final region in energyRegions) {
      if (_regionOverlapFraction(region, vadRegions) > 0.45) {
        continue;
      }
      if (!_confirmVocalRegion(
        region,
        vocalStem: vocalStem,
        drumsStem: drumsStem,
        sampleRate: sampleRate,
      )) {
        continue;
      }
      merged.add(region);
    }

    return _mergeRegions(
      merged,
      gap: ProcessingConstants.vocalRegionMergeGapSeconds,
    );
  }

  bool _confirmVocalRegion(
    (double, double) region, {
    required Float32List vocalStem,
    Float32List? drumsStem,
    required int sampleRate,
  }) {
    final stats = _analyzeSectionVocalActivity(
      vocalStem,
      sampleRate,
      region.$1,
      region.$2,
      drumsStem: drumsStem,
    );
    if (stats.meanVocalEnergy < ProcessingConstants.vocalConfirmationMinEnergy) {
      return false;
    }
    if (drumsStem != null &&
        stats.meanMusicEnergy >
            ProcessingConstants.vocalStemMinimalThreshold) {
      final ratio = stats.meanVocalEnergy /
          math.max(stats.meanMusicEnergy, ProcessingConstants.vocalStemMinimalThreshold);
      if (ratio < ProcessingConstants.vocalConfirmationMinRatio) {
        return false;
      }
    }
    return stats.vocalFrameFraction >= 0.35;
  }

  double _regionOverlapFraction(
    (double, double) region,
    List<(double, double)> others,
  ) {
    final duration = region.$2 - region.$1;
    if (duration <= 0) {
      return 0;
    }

    var overlap = 0.0;
    for (final other in others) {
      final start = math.max(region.$1, other.$1);
      final end = math.min(region.$2, other.$2);
      if (end > start) {
        overlap += end - start;
      }
    }
    return (overlap / duration).clamp(0.0, 1.0);
  }

  ({double vocalFrameFraction, double meanVocalEnergy, double meanMusicEnergy})
      _analyzeSectionVocalActivity(
    Float32List vocalStem,
    int sampleRate,
    double start,
    double end, {
    Float32List? drumsStem,
  }) {
    const frameLength = 2048;
    const hopLength = 512;
    final startSample = math.max(0, (start * sampleRate).floor());
    final endSample = math.min(vocalStem.length, (end * sampleRate).floor());
    if (endSample <= startSample) {
      return (
        vocalFrameFraction: 0,
        meanVocalEnergy: 0,
        meanMusicEnergy: 0,
      );
    }

    var vocalFrames = 0;
    var totalFrames = 0;
    var vocalEnergySum = 0.0;
    var musicEnergySum = 0.0;
    final threshold = ProcessingConstants.vocalStemPresentThreshold;

    for (var frameStart = startSample;
        frameStart + frameLength <= endSample;
        frameStart += hopLength) {
      var vocalSum = 0.0;
      for (var i = frameStart; i < frameStart + frameLength; i++) {
        vocalSum += vocalStem[i] * vocalStem[i];
      }
      final vocalRms = math.sqrt(vocalSum / frameLength);

      var musicRms = 0.0;
      if (drumsStem != null) {
        var musicSum = 0.0;
        for (var i = frameStart; i < frameStart + frameLength; i++) {
          if (i < drumsStem.length) {
            musicSum += drumsStem[i] * drumsStem[i];
          }
        }
        musicRms = math.sqrt(musicSum / frameLength);
      }

      totalFrames++;
      vocalEnergySum += vocalRms;
      musicEnergySum += musicRms;
      if (_isVocalFrame(
        vocalRms: vocalRms,
        musicRms: musicRms,
        threshold: threshold,
      )) {
        vocalFrames++;
      }
    }

    if (totalFrames == 0) {
      return (
        vocalFrameFraction: 0,
        meanVocalEnergy: 0,
        meanMusicEnergy: 0,
      );
    }

    return (
      vocalFrameFraction: vocalFrames / totalFrames,
      meanVocalEnergy: vocalEnergySum / totalFrames,
      meanMusicEnergy: musicEnergySum / totalFrames,
    );
  }

  bool _isInstrumentalOnlyRegion({
    required double start,
    required double end,
    required Float32List vocalStem,
    Float32List? drumsStem,
    required int sampleRate,
    double? minDuration,
    bool structuralGap = false,
    bool edgeSection = false,
  }) {
    final duration = end - start;
    if (duration < (minDuration ?? ProcessingConstants.minStructureGapSeconds)) {
      return false;
    }

    final stats = _analyzeSectionVocalActivity(
      vocalStem,
      sampleRate,
      start,
      end,
      drumsStem: drumsStem,
    );

    // Strict pass — high-confidence instrumental-only.
    if (stats.vocalFrameFraction <=
            ProcessingConstants.instrumentalMaxVocalFrameFraction &&
        stats.meanVocalEnergy <
            ProcessingConstants.instrumentalMaxVocalEnergy) {
      if (drumsStem == null) {
        return true;
      }
      if (stats.meanMusicEnergy <
          ProcessingConstants.instrumentalMinMusicEnergy) {
        return duration >= ProcessingConstants.minStructureInterludeSeconds &&
            stats.meanVocalEnergy <
                ProcessingConstants.vocalStemMinimalThreshold;
      }
      final ratio = stats.meanVocalEnergy /
          math.max(
            stats.meanMusicEnergy,
            ProcessingConstants.vocalStemMinimalThreshold,
          );
      if (ratio <= ProcessingConstants.instrumentalMaxVocalToMusicRatio) {
        return true;
      }
    }

    // Prelude / postlude — positional sections; music present, vocals not dominant.
    if (edgeSection) {
      if (drumsStem == null) {
        return stats.meanVocalEnergy <
            ProcessingConstants.vocalStemPresentThreshold * 2.5;
      }
      if (stats.meanMusicEnergy >=
          ProcessingConstants.instrumentalMinMusicEnergy * 0.5) {
        final ratio = stats.meanVocalEnergy /
            math.max(
              stats.meanMusicEnergy,
              ProcessingConstants.vocalStemMinimalThreshold,
            );
        return ratio <= ProcessingConstants.structuralGapMaxVocalToMusicRatio;
      }
      return stats.vocalFrameFraction <=
          ProcessingConstants.structuralGapMaxVocalFrameFraction;
    }

    // Interludes between sung blocks — trust structure when music is active.
    if (structuralGap) {
      if (drumsStem == null) {
        return stats.vocalFrameFraction <=
            ProcessingConstants.structuralGapMaxVocalFrameFraction;
      }
      if (stats.meanMusicEnergy < ProcessingConstants.interludeDrumsMinEnergy) {
        return duration >= ProcessingConstants.minStructureInterludeSeconds &&
            stats.vocalFrameFraction <=
                ProcessingConstants.structuralGapMaxVocalFrameFraction;
      }
      final ratio = stats.meanVocalEnergy /
          math.max(
            stats.meanMusicEnergy,
            ProcessingConstants.vocalStemMinimalThreshold,
          );
      return stats.vocalFrameFraction <=
              ProcessingConstants.structuralGapMaxVocalFrameFraction &&
          stats.meanVocalEnergy <=
              ProcessingConstants.structuralGapMaxVocalEnergy &&
          ratio <= ProcessingConstants.structuralGapMaxVocalToMusicRatio;
    }

    return false;
  }

  /// SVAD marked this window vocal-less; allow moderate stem bleed on long breaks.
  bool _passesSvadNonVocalInterlude({
    required double start,
    required double end,
    required Float32List vocalStem,
    Float32List? drumsStem,
    required int sampleRate,
  }) {
    if (end - start < ProcessingConstants.minStructureInterludeSeconds) {
      return false;
    }

    final stats = _analyzeSectionVocalActivity(
      vocalStem,
      sampleRate,
      start,
      end,
      drumsStem: drumsStem,
    );

    if (stats.vocalFrameFraction >
        ProcessingConstants.structuralGapMaxVocalFrameFraction) {
      return false;
    }

    if (drumsStem == null) {
      return stats.meanVocalEnergy <=
          ProcessingConstants.structuralGapMaxVocalEnergy;
    }

    if (stats.meanMusicEnergy < ProcessingConstants.interludeDrumsMinEnergy) {
      return false;
    }

    final ratio = stats.meanVocalEnergy /
        math.max(
          stats.meanMusicEnergy,
          ProcessingConstants.vocalStemMinimalThreshold,
        );
    return ratio <= ProcessingConstants.structuralGapMaxVocalToMusicRatio;
  }

  /// Interlude passes strict stem check, or relaxed check for SVAD vocal-less spans.
  bool _passesInterludeInstrumentalCheck({
    required double start,
    required double end,
    required Float32List vocalStem,
    Float32List? drumsStem,
    required int sampleRate,
    required bool allowRelaxed,
  }) {
    final minDuration = ProcessingConstants.minStructureInterludeSeconds;
    if (_isInstrumentalOnlyRegion(
      start: start,
      end: end,
      vocalStem: vocalStem,
      drumsStem: drumsStem,
      sampleRate: sampleRate,
      minDuration: minDuration,
      structuralGap: false,
    )) {
      return true;
    }
    if (!allowRelaxed) {
      return false;
    }
    if (_isInstrumentalOnlyRegion(
      start: start,
      end: end,
      vocalStem: vocalStem,
      drumsStem: drumsStem,
      sampleRate: sampleRate,
      minDuration: minDuration,
      structuralGap: true,
    )) {
      return true;
    }
    return _passesSvadNonVocalInterlude(
      start: start,
      end: end,
      vocalStem: vocalStem,
      drumsStem: drumsStem,
      sampleRate: sampleRate,
    );
  }

  /// Remove raw vocal islands from a gap, returning the longest instrumental span.
  List<(double, double)> _carveInstrumentalSpansFromGap(
    double gapStart,
    double gapEnd,
    List<(double, double)> rawVocalRegions,
  ) {
    final sorted = List<(double, double)>.from(rawVocalRegions)
      ..sort((a, b) => a.$1.compareTo(b.$1));

    final spans = <(double, double)>[];
    var cursor = gapStart;

    for (final (vStart, vEnd) in sorted) {
      if (vEnd <= gapStart) {
        continue;
      }
      if (vStart >= gapEnd) {
        break;
      }
      final overlapStart = math.max(vStart, gapStart);
      final overlapEnd = math.min(vEnd, gapEnd);
      if (overlapStart > cursor + 0.05) {
        spans.add((cursor, overlapStart));
      }
      cursor = math.max(cursor, overlapEnd);
    }

    if (gapEnd > cursor + 0.05) {
      spans.add((cursor, gapEnd));
    }

    if (spans.isEmpty) {
      return [(gapStart, gapEnd)];
    }

    return spans;
  }

  List<(double, double)> _filterRegionsByMinDuration(
    List<(double, double)> regions,
    double minDuration,
  ) {
    return regions.where((region) => region.$2 - region.$1 >= minDuration).toList();
  }

  List<Segment> _partsToSegments(
    List<(double, double)> parts,
    Float32List vocalStem,
    int sampleRate, {
    required String labelPrefix,
  }) {
    final presentThreshold = ProcessingConstants.vocalStemPresentThreshold;
    final minimalThreshold = ProcessingConstants.vocalStemMinimalThreshold;

    return parts
        .map(
          (part) {
            final energy =
                _sectionEnergy(vocalStem, sampleRate, part.$1, part.$2);
            final isMinimal =
                energy >= minimalThreshold && energy < presentThreshold;
            return Segment(
              id:
                  '${labelPrefix}_${part.$1.toStringAsFixed(2)}_${part.$2.toStringAsFixed(2)}',
              type: SegmentType.unknown,
              startSeconds: _round3(part.$1),
              endSeconds: _round3(part.$2),
              hasVocals: false,
              confidence: (0.88 - (energy / presentThreshold).clamp(0.0, 1.0) * 0.18)
                  .clamp(0.65, 0.92),
              label: isMinimal ? 'vocal minimal' : 'vocal-less',
            );
          },
        )
        .toList();
  }

  /// Step 4 prep — merge raw detections into a few sung blocks (ignore short blips).
  List<(double, double)> _buildStructureVocalBlocks(
    List<(double, double)> rawRegions,
  ) {
    final sorted = List<(double, double)>.from(rawRegions)
      ..sort((a, b) => a.$1.compareTo(b.$1));

    if (sorted.isEmpty) {
      return [];
    }

    final filtered = sorted.where((region) {
      final duration = region.$2 - region.$1;
      if (duration < ProcessingConstants.structureMicroVocalMaxSeconds) {
        return false;
      }
      if (region.$1 < ProcessingConstants.structurePreludeMinStartSeconds &&
          duration < 8) {
        return false;
      }
      return true;
    }).toList();

    final source = filtered.isEmpty ? sorted : filtered;

    final pass1 = _mergeRegions(
      source,
      gap: ProcessingConstants.structureVocalMergeGapSeconds,
    );

    return _mergeRegions(
      pass1,
      gap: ProcessingConstants.structureVocalSecondMergeGapSeconds,
    );
  }

  /// First sustained vocal onset on the stem (first sung word / line).
  double _findFirstSustainedVocalOnset(
    Float32List vocalStem,
    int sampleRate, {
    Float32List? drumsStem,
  }) {
    if (vocalStem.isEmpty) {
      return 0;
    }

    const frameLength = 2048;
    const hopLength = 512;
    final rmsValues = <double>[];
    final musicRmsValues = <double>[];
    final frameStarts = <double>[];

    for (var start = 0; start + frameLength <= vocalStem.length; start += hopLength) {
      var sum = 0.0;
      for (var i = start; i < start + frameLength; i++) {
        sum += vocalStem[i] * vocalStem[i];
      }
      rmsValues.add(math.sqrt(sum / frameLength));
      frameStarts.add(start / sampleRate);

      if (drumsStem != null) {
        var musicSum = 0.0;
        for (var i = start; i < start + frameLength; i++) {
          if (i < drumsStem.length) {
            musicSum += drumsStem[i] * drumsStem[i];
          }
        }
        musicRmsValues.add(math.sqrt(musicSum / frameLength));
      }
    }

    if (rmsValues.isEmpty) {
      return 0;
    }

    final sorted = List<double>.from(rmsValues)..sort();
    final quietIndex =
        (sorted.length * 0.20).floor().clamp(0, sorted.length - 1);
    final midIndex =
        (sorted.length * 0.50).floor().clamp(0, sorted.length - 1);
    final onThreshold = math.max(
      ProcessingConstants.vocalStemPresentThreshold,
      sorted[quietIndex] +
          (sorted[midIndex] - sorted[quietIndex]) *
              ProcessingConstants.vocalStemAdaptiveBlend,
    );

    var vocalRun = 0;
    for (var index = 0; index < rmsValues.length; index++) {
      final musicRms = drumsStem != null && index < musicRmsValues.length
          ? musicRmsValues[index]
          : 0.0;
      if (_isVocalFrame(
        vocalRms: rmsValues[index],
        musicRms: musicRms,
        threshold: onThreshold,
      )) {
        vocalRun++;
        if (vocalRun >= ProcessingConstants.vocalOnsetMinFrames) {
          return frameStarts[index - vocalRun + 1];
        }
      } else {
        vocalRun = 0;
      }
    }

    return 0;
  }

  /// Prelude ends at the first real vocals (instrumental-only before that). Returns 0 if none.
  double _findPreludeEndSeconds(
    List<(double, double)> rawVocalRegions, {
    required Float32List vocalStem,
    Float32List? drumsStem,
    required int sampleRate,
  }) {
    final stemOnset = _findFirstSustainedVocalOnset(
      vocalStem,
      sampleRate,
      drumsStem: drumsStem,
    );

    final sortedRaw = List<(double, double)>.from(rawVocalRegions)
      ..sort((a, b) => a.$1.compareTo(b.$1));

    double? confirmedStart;
    for (final region in sortedRaw) {
      if (_confirmVocalRegion(
        region,
        vocalStem: vocalStem,
        drumsStem: drumsStem,
        sampleRate: sampleRate,
      )) {
        confirmedStart = region.$1;
        break;
      }
    }

    var candidate = 0.0;
    if (stemOnset > 0 && confirmedStart != null) {
      candidate = math.min(stemOnset, confirmedStart);
    } else if (stemOnset > 0) {
      candidate = stemOnset;
    } else if (confirmedStart != null) {
      candidate = confirmedStart;
    } else if (sortedRaw.isNotEmpty) {
      candidate = sortedRaw.first.$1;
    }

    if (candidate <= 0) {
      return 0;
    }

    if (_isInstrumentalOnlyRegion(
      start: 0,
      end: candidate,
      vocalStem: vocalStem,
      drumsStem: drumsStem,
      sampleRate: sampleRate,
      minDuration: ProcessingConstants.minStructureGapSeconds,
      edgeSection: true,
    )) {
      return candidate;
    }

    return stemOnset > 0 ? stemOnset : 0;
  }

  /// Outro begins after the last raw vocal line in the final sung block.
  double _findPostludeStartSeconds(
    List<(double, double)> blocks,
    List<(double, double)> rawVocalRegions,
    double duration,
  ) {
    if (blocks.isEmpty) {
      return duration;
    }

    final lastBlock = blocks.last;
    final sortedRaw = List<(double, double)>.from(rawVocalRegions)
      ..sort((a, b) => a.$1.compareTo(b.$1));

    double? lastVocalEnd;
    for (final (start, end) in sortedRaw.reversed) {
      if (start > lastBlock.$2 + 2.0) {
        continue;
      }
      if (end < lastBlock.$1 - 1.0) {
        break;
      }
      if (end - start < ProcessingConstants.minVocalRegionSeconds) {
        continue;
      }
      lastVocalEnd = end;
      break;
    }

    return lastVocalEnd ?? lastBlock.$2;
  }

  /// Instrumental-only breaks: vocal-less parts + validated carved block gaps.
  List<(double, double)> _finalizeInterludeGaps({
    required List<(double, double)> nonVocalParts,
    required List<(double, double)> rawVocalRegions,
    required List<(double, double)> structureBlocks,
    required double preludeEnd,
    required double mainVocalEnd,
    required Float32List vocalStem,
    Float32List? drumsStem,
    required int sampleRate,
  }) {
    final sortedRaw = List<(double, double)>.from(rawVocalRegions)
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final edgeTolerance = ProcessingConstants.structureEdgeToleranceSeconds;
    final minInterlude = ProcessingConstants.minStructureInterludeSeconds;
    final refined = <(double, double)>[];
    final seen = <String>{};

    void tryAdd(
      double gapStart,
      double gapEnd, {
      required bool fromSvadNonVocalPart,
    }) {
      if (gapEnd <= preludeEnd + edgeTolerance ||
          gapStart >= mainVocalEnd - edgeTolerance) {
        return;
      }

      final start = _refineInterludeStart(gapStart, sortedRaw);
      final end = _refineInterludeEnd(gapEnd, sortedRaw);
      if (end - start < minInterlude) {
        return;
      }

      if (_isGapInsideStructureBlock(start, end, structureBlocks) &&
          end - start < ProcessingConstants.minIntraBlockInterludeSeconds) {
        return;
      }

      if (!_passesInterludeInstrumentalCheck(
        start: start,
        end: end,
        vocalStem: vocalStem,
        drumsStem: drumsStem,
        sampleRate: sampleRate,
        allowRelaxed: fromSvadNonVocalPart,
      )) {
        return;
      }

      final key =
          '${start.toStringAsFixed(2)}-${end.toStringAsFixed(2)}';
      if (seen.contains(key)) {
        return;
      }
      seen.add(key);
      refined.add((start, end));
    }

    for (final (partStart, partEnd) in nonVocalParts) {
      tryAdd(partStart, partEnd, fromSvadNonVocalPart: true);
    }

    for (final (gapStart, gapEnd)
        in _gapsBetweenStructureBlocks(structureBlocks)) {
      final spans = _carveInstrumentalSpansFromGap(
        gapStart,
        gapEnd,
        sortedRaw,
      );
      (double, double)? best;
      var bestDuration = 0.0;
      for (final (spanStart, spanEnd) in spans) {
        final spanDuration = spanEnd - spanStart;
        if (spanDuration < minInterlude) {
          continue;
        }
        final refinedStart = _refineInterludeStart(spanStart, sortedRaw);
        final refinedEnd = _refineInterludeEnd(spanEnd, sortedRaw);
        final duration = refinedEnd - refinedStart;
        if (duration < minInterlude) {
          continue;
        }
        if (!_passesInterludeInstrumentalCheck(
          start: refinedStart,
          end: refinedEnd,
          vocalStem: vocalStem,
          drumsStem: drumsStem,
          sampleRate: sampleRate,
          allowRelaxed: false,
        )) {
          continue;
        }
        if (duration > bestDuration) {
          best = (refinedStart, refinedEnd);
          bestDuration = duration;
        }
      }
      if (best != null) {
        tryAdd(best.$1, best.$2, fromSvadNonVocalPart: false);
      }
    }

    return _mergeRegions(
      refined,
      gap: ProcessingConstants.instrumentalRegionMergeGapSeconds,
    );
  }

  /// True when the gap lies entirely inside one merged sung block (not between blocks).
  bool _isGapInsideStructureBlock(
    double gapStart,
    double gapEnd,
    List<(double, double)> structureBlocks,
  ) {
    const margin = 0.35;
    for (final (blockStart, blockEnd) in structureBlocks) {
      if (gapStart >= blockStart + margin && gapEnd <= blockEnd - margin) {
        return true;
      }
    }
    return false;
  }

  /// Pull interlude start earlier to where singing last stopped (not block tail).
  double _refineInterludeStart(
    double gapStart,
    List<(double, double)> rawVocalRegions,
  ) {
    double? lastVocalEnd;
    for (final (_, end) in rawVocalRegions) {
      if (end <= gapStart + 0.5 && end > (lastVocalEnd ?? -1)) {
        lastVocalEnd = end;
      }
    }
    if (lastVocalEnd != null &&
        gapStart - lastVocalEnd <=
            ProcessingConstants.interludeRefineStartMaxLookbackSeconds) {
      return lastVocalEnd;
    }
    return gapStart;
  }

  /// End interlude when singing resumes (first raw vocal in the gap).
  double _refineInterludeEnd(
    double gapEnd,
    List<(double, double)> rawVocalRegions,
  ) {
    double? firstVocalStart;
    for (final (start, _) in rawVocalRegions) {
      if (start >= gapEnd - 1.0) {
        firstVocalStart = start;
        break;
      }
    }
    if (firstVocalStart != null &&
        firstVocalStart > gapEnd -
            ProcessingConstants.interludeRefineEndMaxLookaheadSeconds &&
        firstVocalStart <= gapEnd + 2) {
      return firstVocalStart;
    }
    return gapEnd;
  }

  /// Gaps between merged vocal blocks (instrumental breaks).
  List<(double, double)> _gapsBetweenStructureBlocks(
    List<(double, double)> blocks, {
    double? minGapSeconds,
  }) {
    if (blocks.length < 2) {
      return [];
    }

    final minGap =
        minGapSeconds ?? ProcessingConstants.minStructureInterludeSeconds;
    final gaps = <(double, double)>[];
    for (var index = 0; index < blocks.length - 1; index++) {
      final gapStart = blocks[index].$2;
      final gapEnd = blocks[index + 1].$1;
      final gapDuration = gapEnd - gapStart;
      if (gapDuration >= minGap) {
        gaps.add((gapStart, gapEnd));
      }
    }
    return gaps;
  }

  /// Step 4 — Prelude / Interlude / Postlude from structure blocks (not raw blips).
  List<Segment> _mapStructureBlocksToMarkers({
    required double duration,
    required List<(double, double)> structureBlocks,
    required List<(double, double)> rawVocalRegions,
    required Float32List vocalStem,
    Float32List? drumsStem,
    required int sampleRate,
    List<(double, double)> nonVocalParts = const [],
  }) {
    if (duration <= 0) {
      return [];
    }

    final minGap = ProcessingConstants.minStructureGapSeconds;
    final markers = <Segment>[];

    if (structureBlocks.isEmpty) {
      if (duration >= minGap) {
        markers.add(_structureSegment(
          SegmentType.prelude,
          0,
          duration,
          vocalStem,
          drumsStem,
          sampleRate,
        ));
      }
      return markers;
    }

    final preludeEnd = _findPreludeEndSeconds(
      rawVocalRegions,
      vocalStem: vocalStem,
      drumsStem: drumsStem,
      sampleRate: sampleRate,
    );
    final postludeStart =
        _findPostludeStartSeconds(structureBlocks, rawVocalRegions, duration);

    if (preludeEnd >= minGap) {
      markers.add(_structureSegment(
        SegmentType.prelude,
        0,
        preludeEnd,
        vocalStem,
        drumsStem,
        sampleRate,
      ));
    }

    if (duration - postludeStart >= minGap) {
      markers.add(_structureSegment(
        SegmentType.postlude,
        postludeStart,
        duration,
        vocalStem,
        drumsStem,
        sampleRate,
      ));
    }

    final interludeGaps = _finalizeInterludeGaps(
      nonVocalParts: nonVocalParts,
      rawVocalRegions: rawVocalRegions,
      structureBlocks: structureBlocks,
      preludeEnd: preludeEnd,
      mainVocalEnd: postludeStart,
      vocalStem: vocalStem,
      drumsStem: drumsStem,
      sampleRate: sampleRate,
    );
    var interludeIndex = 0;

    for (final (start, end) in interludeGaps) {
      interludeIndex++;
      markers.add(_structureSegment(
        SegmentType.interlude,
        start,
        end,
        vocalStem,
        drumsStem,
        sampleRate,
        interludeIndex: interludeIndex,
      ));
    }

    markers.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
    return markers;
  }

  /// Instrumental energy reference for prelude / interlude / postlude rules.
  Future<Float32List> _drumsStemForStructure({
    required String? mixWavPath,
    required Float32List vocalMono,
    required String separatedInstPath,
  }) async {
    if (ProcessingConstants.structureUseMixMinusVocal &&
        mixWavPath != null &&
        mixWavPath.isNotEmpty &&
        vocalMono.isNotEmpty) {
      final mixMinus = await computeMixMinusVocalMono(
        wavPath: mixWavPath,
        vocalMono: vocalMono,
      );
      if (mixMinus.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[Structure] drumsStem = mix_mono − vocal_mono (${mixMinus.length} samples)',
          );
        }
        return mixMinus;
      }
    }
    return loadMonoFromWav(separatedInstPath);
  }

  /// Post-process structure markers: resolve overlaps, validate layout, re-index.
  List<Segment> _finalizeStructureSegments({
    required List<Segment> markers,
    required Float32List vocalStem,
    Float32List? drumsStem,
    required int sampleRate,
    required double duration,
    required List<(double, double)> vocalRegions,
    required double preludeEnd,
    required double mainVocalEnd,
    required List<(double, double)> structureBlocks,
  }) {
    if (markers.isEmpty) {
      return markers;
    }

    final minGap = ProcessingConstants.minStructureGapSeconds;
    final validated = markers
        .where(
          (segment) => segment.endSeconds - segment.startSeconds >= minGap,
        )
        .toList();

    validated.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    final resolved = <Segment>[];
    for (final segment in validated) {
      if (resolved.isEmpty) {
        resolved.add(segment);
        continue;
      }

      final previous = resolved.last;
      if (segment.startSeconds >= previous.endSeconds - 0.05) {
        resolved.add(segment);
        continue;
      }

      if (segment.confidence > previous.confidence) {
        resolved[resolved.length - 1] = segment;
      }
    }

    final layoutValidated = _validateStructureMarkers(
      markers: resolved,
      vocalRegions: vocalRegions,
      duration: duration,
      vocalStem: vocalStem,
      drumsStem: drumsStem,
      sampleRate: sampleRate,
      preludeEnd: preludeEnd,
      mainVocalEnd: mainVocalEnd,
      structureBlocks: structureBlocks,
    );

    var interludeIndex = 0;
    return layoutValidated.map((segment) {
      if (segment.type != SegmentType.interlude) {
        return segment;
      }
      interludeIndex++;
      return _structureSegment(
        SegmentType.interlude,
        segment.startSeconds,
        segment.endSeconds,
        vocalStem,
        drumsStem,
        sampleRate,
        interludeIndex: interludeIndex,
      );
    }).toList();
  }

  /// Resolves overlaps and enforces prelude / interlude / postlude layout.
  List<Segment> _validateStructureMarkers({
    required List<Segment> markers,
    required List<(double, double)> vocalRegions,
    required double duration,
    required Float32List vocalStem,
    Float32List? drumsStem,
    required int sampleRate,
    required double preludeEnd,
    required double mainVocalEnd,
    required List<(double, double)> structureBlocks,
  }) {
    if (markers.isEmpty) {
      return markers;
    }

    final minGap = ProcessingConstants.minStructureGapSeconds;
    final edgeTol = ProcessingConstants.structureEdgeToleranceSeconds;

    final adjusted = <Segment>[];

    for (final segment in markers) {
      switch (segment.type) {
        case SegmentType.prelude:
          final start = 0.0;
          var end = preludeEnd > 0
              ? preludeEnd.clamp(0.0, duration)
              : segment.endSeconds.clamp(0.0, duration);
          if (end <= 0 || end - start < minGap) {
            continue;
          }
          if (!_isInstrumentalOnlyRegion(
            start: start,
            end: end,
            vocalStem: vocalStem,
            drumsStem: drumsStem,
            sampleRate: sampleRate,
            minDuration: minGap,
            edgeSection: true,
          )) {
            continue;
          }
          adjusted.add(
            _structureSegment(
              SegmentType.prelude,
              start,
              end,
              vocalStem,
              drumsStem,
              sampleRate,
            ),
          );
        case SegmentType.interlude:
          var start = segment.startSeconds;
          var end = segment.endSeconds;
          if (end <= preludeEnd + edgeTol || start >= mainVocalEnd - edgeTol) {
            continue;
          }
          if (_isGapInsideStructureBlock(start, end, structureBlocks) &&
              end - start < ProcessingConstants.minIntraBlockInterludeSeconds) {
            continue;
          }
          if (end - start < ProcessingConstants.minStructureInterludeSeconds) {
            continue;
          }
          if (!_passesInterludeInstrumentalCheck(
            start: start,
            end: end,
            vocalStem: vocalStem,
            drumsStem: drumsStem,
            sampleRate: sampleRate,
            allowRelaxed: true,
          )) {
            continue;
          }
          adjusted.add(
            _structureSegment(
              SegmentType.interlude,
              start,
              end,
              vocalStem,
              drumsStem,
              sampleRate,
            ),
          );
        case SegmentType.postlude:
          final start = math.max(
            segment.startSeconds,
            mainVocalEnd > 0 ? mainVocalEnd - edgeTol : segment.startSeconds,
          );
          final end = duration;
          if (end - start < minGap) {
            continue;
          }
          adjusted.add(
            _structureSegment(
              SegmentType.postlude,
              start,
              end,
              vocalStem,
              drumsStem,
              sampleRate,
            ),
          );
        case SegmentType.unknown:
          adjusted.add(segment);
      }
    }

    adjusted.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    final merged = <Segment>[];
    for (final segment in adjusted) {
      if (merged.isEmpty) {
        merged.add(segment);
        continue;
      }
      final prev = merged.last;
      if (segment.type == SegmentType.interlude &&
          prev.type == SegmentType.interlude &&
          segment.startSeconds - prev.endSeconds <=
              ProcessingConstants.interludeSourceMergeGapSeconds) {
        merged[merged.length - 1] = _structureSegment(
          SegmentType.interlude,
          prev.startSeconds,
          math.max(prev.endSeconds, segment.endSeconds),
          vocalStem,
          drumsStem,
          sampleRate,
          interludeIndex: 1,
        );
        continue;
      }
      if (segment.startSeconds < prev.endSeconds - 0.05) {
        if (segment.confidence > prev.confidence) {
          merged[merged.length - 1] = segment;
        }
        continue;
      }
      merged.add(segment);
    }

    return merged;
  }

  VocalModelOutput _buildVocalModelOutput({
    required String method,
    required double duration,
    required int sampleRate,
    required _PipelineAnalysis analysis,
    required List<Segment> vocalTimestamps,
    required List<Segment> nonVocalOppositeSegments,
    required List<Segment> nonVocalPartSegments,
    required List<Segment> structureSegments,
    String? model,
  }) {
    final buffer = StringBuffer()
      ..writeln('=== Cliploops Vocal Model Pipeline ===')
      ..writeln('method: $method');
    if (model != null) {
      buffer.writeln('stem_model: $model');
    }
    buffer
      ..writeln('duration_seconds: ${_round3(duration)}')
      ..writeln('sample_rate: $sampleRate')
      ..writeln('')
      ..writeln('--- Step 1: vocal_regions (${analysis.vocalRegions.length}) ---');

    for (final (start, end) in analysis.vocalRegions) {
      buffer.writeln(
        '  vocal  ${_formatTimestamp(start)} -> ${_formatTimestamp(end)}  '
        '(${_round3(end - start)}s)',
      );
    }

    buffer.writeln('');
    buffer.writeln(
      '--- Step 2: non_vocal_opposite (${analysis.nonVocalOpposite.length}) ---',
    );

    for (final (start, end) in analysis.nonVocalOpposite) {
      buffer.writeln(
        '  opposite  ${_formatTimestamp(start)} -> ${_formatTimestamp(end)}  '
        '(${_round3(end - start)}s)',
      );
    }

    buffer.writeln('');
    buffer.writeln(
      '--- Step 3: non_vocal_parts (${analysis.nonVocalParts.length}) ---',
    );

    for (final (start, end) in analysis.nonVocalParts) {
      buffer.writeln(
        '  part  ${_formatTimestamp(start)} -> ${_formatTimestamp(end)}  '
        '(${_round3(end - start)}s)',
      );
    }

    buffer.writeln('');
    buffer.writeln(
      '--- Step 3b: structure_vocal_blocks (${analysis.structureBlocks.length}) ---',
    );
    for (final (start, end) in analysis.structureBlocks) {
      buffer.writeln(
        '  block  ${_formatTimestamp(start)} -> ${_formatTimestamp(end)}  '
        '(${_round3(end - start)}s)',
      );
    }

    buffer.writeln('');
    buffer.writeln(
      '--- Step 3c: prelude_end ${_formatTimestamp(analysis.preludeEnd)} ---',
    );
    buffer.writeln('');
    buffer.writeln(
      '--- Step 3d: interlude_candidates (${analysis.interludeCandidates.length}) ---',
    );
    for (final (start, end) in analysis.interludeCandidates) {
      buffer.writeln(
        '  interlude_candidate  ${_formatTimestamp(start)} -> '
        '${_formatTimestamp(end)}  (${_round3(end - start)}s)',
      );
    }
    buffer.writeln('');
    final interludeCount = structureSegments
        .where((segment) => segment.type == SegmentType.interlude)
        .length;
    buffer.writeln(
      '--- Step 4: prelude_interlude_postlude (${structureSegments.length}) — '
      '$interludeCount interlude(s) ---',
    );

    for (final segment in structureSegments) {
      buffer.writeln(
        '  ${segment.type.name.padRight(10)} '
        '${_formatTimestamp(segment.startSeconds)} -> '
        '${_formatTimestamp(segment.endSeconds)}  '
        'label=${segment.label ?? '-'}',
      );
    }

    return VocalModelOutput(
      vocalTimestamps: vocalTimestamps,
      nonVocalOppositeSegments: nonVocalOppositeSegments,
      nonVocalPartSegments: nonVocalPartSegments,
      rawLog: buffer.toString().trimRight(),
    );
  }

  void _logVocalModelOutput(String rawLog) {
    debugPrint(rawLog);
  }

  /// Bold timing summary for `flutter run` / Xcode console after ML + SVAD finish.
  void _logScanTimingComplete({
    required String methodLabel,
    required Duration total,
    required Duration mlSeparation,
    required Duration svadAndStructure,
  }) {
    final totalLabel = _formatScanDuration(total);
    final mlLabel = _formatScanDuration(mlSeparation);
    final svadLabel = _formatScanDuration(svadAndStructure);

    debugPrint('');
    debugPrint(_terminalBold('══════════════════════════════════════════════════'));
    debugPrint(
      _terminalBold('$methodLabel scan completed in $totalLabel'),
    );
    debugPrint(_terminalBold('  ML separation:     $mlLabel'));
    debugPrint(_terminalBold('  SVAD + structure:  $svadLabel'));
    debugPrint(_terminalBold('══════════════════════════════════════════════════'));
    debugPrint('');
  }

  String _formatScanDuration(Duration duration) {
    if (duration.inMinutes > 0) {
      final seconds = duration.inSeconds.remainder(60);
      return '${duration.inMinutes}m ${seconds}s';
    }
    if (duration.inSeconds > 0) {
      final tenths = (duration.inMilliseconds % 1000) ~/ 100;
      return tenths > 0
          ? '${duration.inSeconds}.${tenths}s'
          : '${duration.inSeconds}s';
    }
    return '${duration.inMilliseconds}ms';
  }

  String _terminalBold(String text) => '\x1B[1m$text\x1B[0m';

  String _formatTimestamp(double seconds) {
    final total = seconds.floor();
    final minutes = total ~/ 60;
    final secs = total % 60;
    final millis = ((seconds - total) * 1000).round();
    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}.'
        '${millis.toString().padLeft(3, '0')}';
  }

  Segment _structureSegment(
    SegmentType type,
    double start,
    double end,
    Float32List vocalStem,
    Float32List? drumsStem,
    int sampleRate, {
    int? interludeIndex,
  }) {
    final vocalEnergy = _sectionEnergy(vocalStem, sampleRate, start, end);
    final presentThreshold = ProcessingConstants.vocalStemPresentThreshold;
    final minimalThreshold = ProcessingConstants.vocalStemMinimalThreshold;

    final drumsEnergy = drumsStem == null
        ? 0.0
        : _sectionEnergy(drumsStem, sampleRate, start, end);
    final hasDrums = drumsStem != null &&
        drumsEnergy >= ProcessingConstants.interludeDrumsMinEnergy;

    final energyRatio = (vocalEnergy / presentThreshold).clamp(0.0, 1.0);
    var confidence = (0.88 - energyRatio * 0.18).clamp(0.65, 0.92);
    if (hasDrums && vocalEnergy < minimalThreshold) {
      confidence = (confidence + 0.06).clamp(0.0, 0.99);
    }

    final contentLabel = hasDrums && vocalEnergy < presentThreshold
        ? 'drums & beats'
        : 'instrumental';

    final typeLabel = switch (type) {
      SegmentType.prelude => 'Prelude',
      SegmentType.postlude => 'Postlude',
      SegmentType.interlude => 'Interlude $interludeIndex',
      SegmentType.unknown => 'Segment',
    };

    return Segment(
      id: '${type.name}_${_uuid.v4().substring(0, 8)}',
      type: type,
      startSeconds: _round3(start),
      endSeconds: _round3(end),
      hasVocals: false,
      confidence: confidence,
      label: '$typeLabel · $contentLabel',
    );
  }

  List<(double, double)> _mergeRegions(
    List<(double, double)> regions, {
    double gap = 0.35,
  }) {
    if (regions.isEmpty) {
      return [];
    }

    final sorted = List<(double, double)>.from(regions)
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(double, double)>[sorted.first];

    for (var index = 1; index < sorted.length; index++) {
      final (start, end) = sorted[index];
      final last = merged.last;
      if (start - last.$2 <= gap) {
        merged[merged.length - 1] = (last.$1, math.max(last.$2, end));
      } else {
        merged.add((start, end));
      }
    }

    return merged;
  }

  List<(double, double)> _invertRegions(
    List<(double, double)> regions,
    double duration,
  ) {
    if (duration <= 0) {
      return [];
    }

    final sorted = List<(double, double)>.from(regions)
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final inverted = <(double, double)>[];
    var cursor = 0.0;

    for (final (start, end) in sorted) {
      if (start > cursor + 0.25) {
        inverted.add((cursor, start));
      }
      cursor = math.max(cursor, end);
    }

    if (cursor < duration - 0.25) {
      inverted.add((cursor, duration));
    }

    return inverted;
  }

  List<Segment> _regionsToSegments(
    List<(double, double)> regions, {
    required bool hasVocals,
    String? label,
  }) {
    return regions
        .map(
          (region) => Segment(
            id:
                '${hasVocals ? 'vocal' : 'instrumental'}_${region.$1.toStringAsFixed(2)}_${region.$2.toStringAsFixed(2)}',
            type: SegmentType.unknown,
            startSeconds: _round3(region.$1),
            endSeconds: _round3(region.$2),
            hasVocals: hasVocals,
            confidence: hasVocals ? 0.85 : 0.75,
            label: label,
          ),
        )
        .toList();
  }

  double _sectionEnergy(
    Float32List samples,
    int sampleRate,
    double start,
    double end,
  ) {
    final startSample = math.max(0, (start * sampleRate).floor());
    final endSample = math.min(samples.length, (end * sampleRate).floor());
    if (endSample <= startSample) {
      return 0;
    }

    var sum = 0.0;
    for (var i = startSample; i < endSample; i++) {
      sum += samples[i] * samples[i];
    }
    return math.sqrt(sum / (endSample - startSample));
  }

  double _round3(double value) => (value * 1000).round() / 1000;

  StemType _stemType(String name) {
    switch (name) {
      case 'vocals':
        return StemType.vocals;
      case 'accompaniment':
        return StemType.accompaniment;
      case 'drums':
        return StemType.drums;
      case 'bass':
        return StemType.bass;
      case 'piano':
        return StemType.piano;
      default:
        return StemType.other;
    }
  }

  Future<Directory> _stemOutputDirectory(String jobId) async {
    final directory = await getApplicationDocumentsDirectory();
    final stemDirectory = Directory(
      FileHelper.joinPath(
        directory.path,
        AppConstants.stemsCacheDir,
        jobId,
      ),
    );
    await stemDirectory.create(recursive: true);
    return stemDirectory;
  }

  List<int> _int16Le(int value) => [value & 0xff, (value >> 8) & 0xff];

  List<int> _int32Le(int value) => [
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ];
}

class GaplessMixExport {
  const GaplessMixExport({
    required this.wavPath,
    required this.result,
  });

  final String wavPath;
  final GaplessMixResult result;
}

class _StructurePipelineResult {
  const _StructurePipelineResult({
    required this.structureSegments,
    required this.vocalModelOutput,
  });

  final List<Segment> structureSegments;
  final VocalModelOutput vocalModelOutput;
}

class _PipelineAnalysis {
  const _PipelineAnalysis({
    required this.vocalRegions,
    required this.structureBlocks,
    required this.preludeEnd,
    required this.interludeCandidates,
    required this.nonVocalOpposite,
    required this.nonVocalParts,
  });

  final List<(double, double)> vocalRegions;
  final List<(double, double)> structureBlocks;
  final double preludeEnd;
  final List<(double, double)> interludeCandidates;
  final List<(double, double)> nonVocalOpposite;
  final List<(double, double)> nonVocalParts;
}

class PcmAudio {
  const PcmAudio({
    required this.mono,
    required this.left,
    required this.right,
    required this.sampleRate,
  });

  final Float32List mono;
  final Float32List left;
  final Float32List right;
  final int sampleRate;

  double get durationSeconds =>
      sampleRate == 0
          ? 0
          : (left.isNotEmpty ? left.length : mono.length) / sampleRate;
}

class StemPcm {
  const StemPcm({
    required this.samples,
    required this.mono,
  });

  final Float32List samples;
  final Float32List mono;

  double durationSecondsFor(int sampleRate) =>
      sampleRate == 0 ? 0 : mono.length / sampleRate;
}
