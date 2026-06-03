import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Downloads and caches the UVR MDX-Net ONNX model (used for the ORT shape /
/// CPU-fallback session; the NPU path runs the bundled .tflite natively).
class MlModelService {
  MlModelService._();

  static final MlModelService instance = MlModelService._();

  /// UVR MDX-Net vocal model (~28 MB).
  static const String uvrMdxnetUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/source-separation-models/UVR_MDXNET_9482.onnx';

  static const String uvrMdxnetFileName = 'UVR_MDXNET_9482.onnx';

  Future<String>? _uvrDownload;

  /// On-disk path to the UVR MDX-Net ONNX, downloading once if needed.
  Future<String> ensureUvrMdxnet({void Function(int progress)? onProgress}) {
    return _uvrDownload ??= _downloadModel(
      url: uvrMdxnetUrl,
      fileName: uvrMdxnetFileName,
      minBytes: 20_000_000,
      onProgress: onProgress,
    ).catchError((Object e) {
      _uvrDownload = null;
      throw e;
    });
  }

  Future<String> _downloadModel({
    required String url,
    required String fileName,
    required int minBytes,
    void Function(int progress)? onProgress,
  }) async {
    final dir = await getApplicationSupportDirectory();
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
