import 'dart:io';

import 'package:archive/archive.dart';

import 'android_paths_service.dart';

/// Downloads and caches open-source ONNX models used on-device.
class MlModelService {
  MlModelService._();

  static final MlModelService instance = MlModelService._();

  static const String sileroVadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx';

  static const String sileroVadFileName = 'silero_vad.onnx';

  /// Mobile-optimised vocals specialist (~166 MB).
  static const String demucsVocalsUrl =
      'https://huggingface.co/StemSplitio/htdemucs-ft-onnx/resolve/main/htdemucs_ft_vocals_fp16weights.onnx';

  static const String demucsVocalsFileName =
      'htdemucs_ft_vocals_fp16weights.onnx';

  /// Sherpa-onnx Spleeter 2-stems FP16 (~19 MB × 2) — fits iOS RAM limits.
  static const String spleeterArchiveUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/source-separation-models/sherpa-onnx-spleeter-2stems-fp16.tar.bz2';

  static const String spleeterVocalsFileName = 'vocals.fp16.onnx';
  static const String spleeterAccompanimentFileName = 'accompaniment.fp16.onnx';

  /// UVR MDXNET vocal model (~28 MB) — primary separation on Android + iOS.
  static const String uvrMdxnetUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/source-separation-models/UVR_MDXNET_9482.onnx';

  static const String uvrMdxnetFileName = 'UVR_MDXNET_9482.onnx';

  Future<String>? _sileroDownload;
  Future<String>? _demucsVocalsDownload;
  Future<({String vocals, String accompaniment})>? _spleeterDownload;
  Future<String>? _uvrDownload;

  /// Returns the on-disk path to [silero_vad.onnx], downloading once if needed.
  Future<String> ensureSileroVad({void Function(int progress)? onProgress}) {
    return _sileroDownload ??= _downloadSileroVad(onProgress: onProgress);
  }

  /// FT vocals specialist — only model needed for 2-stem separation.
  Future<String> ensureDemucsVocals({
    void Function(int progress)? onProgress,
  }) {
    return _demucsVocalsDownload ??= _downloadModel(
      url: demucsVocalsUrl,
      fileName: demucsVocalsFileName,
      minBytes: 50_000_000,
      onProgress: onProgress,
    );
  }

  /// Spleeter vocals + accompaniment ONNX pair for iOS source separation.
  Future<({String vocals, String accompaniment})> ensureSpleeterModels({
    void Function(int progress)? onProgress,
  }) {
    return _spleeterDownload ??= _downloadSpleeterModels(onProgress: onProgress);
  }

  /// UVR MDXNET vocal extraction model (Android + iOS).
  Future<String> ensureUvrMdxnet({void Function(int progress)? onProgress}) {
    return _uvrDownload ??= _downloadModel(
      url: uvrMdxnetUrl,
      fileName: uvrMdxnetFileName,
      minBytes: 20_000_000,
      onProgress: onProgress,
    );
  }

  Future<({String vocals, String accompaniment})> _downloadSpleeterModels({
    void Function(int progress)? onProgress,
  }) async {
    try {
      final dir = await AndroidPathsService.instance.supportDirectory();
      final modelsDir = Directory('${dir.path}/ml_models/spleeter');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      final vocalsPath = '${modelsDir.path}/$spleeterVocalsFileName';
      final accompanimentPath =
          '${modelsDir.path}/$spleeterAccompanimentFileName';

      final vocalsFile = File(vocalsPath);
      final accompanimentFile = File(accompanimentPath);
      if (await vocalsFile.exists() &&
          await accompanimentFile.exists() &&
          await vocalsFile.length() > 10_000_000 &&
          await accompanimentFile.length() > 10_000_000) {
        onProgress?.call(100);
        return (vocals: vocalsPath, accompaniment: accompanimentPath);
      }

      onProgress?.call(0);
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(spleeterArchiveUrl));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException(
            'Could not download Spleeter models (HTTP ${response.statusCode}).',
          );
        }

        final total = response.contentLength;
        var received = 0;
        final archiveBytes = <int>[];

        await for (final chunk in response) {
          archiveBytes.addAll(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress?.call((received * 85 ~/ total).clamp(0, 85));
          }
        }

        onProgress?.call(88);
        final archive = TarDecoder().decodeBytes(
          BZip2Decoder().decodeBytes(archiveBytes),
        );

        for (final file in archive.files) {
          if (file.isFile && file.name.endsWith('.onnx')) {
            final name = file.name.split('/').last;
            if (name == spleeterVocalsFileName ||
                name == spleeterAccompanimentFileName) {
              await File('${modelsDir.path}/$name').writeAsBytes(file.content);
            }
          }
        }

        if (!await vocalsFile.exists() || !await accompanimentFile.exists()) {
          throw HttpException(
            'Spleeter archive did not contain expected ONNX models.',
          );
        }

        onProgress?.call(100);
        return (vocals: vocalsPath, accompaniment: accompanimentPath);
      } finally {
        client.close();
      }
    } catch (error) {
      _spleeterDownload = null;
      rethrow;
    }
  }

  Future<String> _downloadSileroVad({
    void Function(int progress)? onProgress,
  }) async {
    try {
      return await _downloadModel(
        url: sileroVadUrl,
        fileName: sileroVadFileName,
        minBytes: 1000,
        onProgress: onProgress,
      );
    } catch (error) {
      _sileroDownload = null;
      rethrow;
    }
  }

  Future<String> _downloadModel({
    required String url,
    required String fileName,
    required int minBytes,
    void Function(int progress)? onProgress,
  }) async {
    final dir = await AndroidPathsService.instance.supportDirectory();
    final modelsDir = Directory('${dir.path}/ml_models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    final target = File('${modelsDir.path}/$fileName');
    if (await target.exists() && await target.length() > minBytes) {
      onProgress?.call(100);
      return target.path;
    }

    onProgress?.call(0);
    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'Could not download $fileName (HTTP ${response.statusCode}).',
        );
      }

      final total = response.contentLength;
      var received = 0;
      sink = target.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received * 100 ~/ total).clamp(0, 99));
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;
      onProgress?.call(100);
      return target.path;
    } finally {
      if (sink != null) {
        await sink.close();
      }
      client.close();
    }
  }
}
