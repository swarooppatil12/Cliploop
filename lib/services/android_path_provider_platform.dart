import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'android_paths_service.dart';

/// Routes all [path_provider] calls through [AndroidPathsService] on Android.
///
/// The stock path_provider_android Pigeon handler fails to connect on some
/// Samsung / Android 16 builds, which breaks ML separation (temp WAV decode).
class AndroidPathProviderPlatform extends PathProviderPlatform {
  final AndroidPathsService _paths = AndroidPathsService.instance;

  @override
  Future<String?> getTemporaryPath() => _paths.cachePath();

  @override
  Future<String?> getApplicationCachePath() => _paths.cachePath();

  @override
  Future<String?> getApplicationDocumentsPath() => _paths.documentsPath();

  @override
  Future<String?> getApplicationSupportPath() => _paths.supportPath();

  @override
  Future<String?> getExternalStoragePath() async {
    if (!Platform.isAndroid) {
      return null;
    }
    return _paths.documentsPath();
  }

  @override
  Future<List<String>?> getExternalCachePaths() async {
    final cache = await _paths.cachePath();
    return [cache];
  }

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async {
    if (type == StorageDirectory.downloads && Platform.isAndroid) {
      const downloads = '/storage/emulated/0/Download';
      if (await Directory(downloads).exists()) {
        return [downloads];
      }
    }
    final docs = await _paths.documentsPath();
    return [docs];
  }

  @override
  Future<String?> getDownloadsPath() async {
    final paths = await getExternalStoragePaths(
      type: StorageDirectory.downloads,
    );
    if (paths == null || paths.isEmpty) {
      return null;
    }
    return paths.first;
  }
}
