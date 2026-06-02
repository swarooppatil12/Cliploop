import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Android app storage paths via MethodChannel — never uses path_provider on Android.
class AndroidPathsService {
  AndroidPathsService._();

  static final AndroidPathsService instance = AndroidPathsService._();

  static const MethodChannel _channel = MethodChannel('com.swaroop.app/paths');

  String? _documentsPath;
  String? _supportPath;
  String? _cachePath;

  Future<String> cachePath() async {
    if (!Platform.isAndroid) {
      return (await getTemporaryDirectory()).path;
    }
    if (_cachePath != null) {
      return _cachePath!;
    }
    final path = await _channel.invokeMethod<String>('getAppCachePath');
    if (path == null || path.isEmpty) {
      throw StateError('Empty cache path from Android');
    }
    _cachePath = path;
    return path;
  }

  Future<String> documentsPath() async {
    if (!Platform.isAndroid) {
      return (await getApplicationDocumentsDirectory()).path;
    }
    if (_documentsPath != null) {
      return _documentsPath!;
    }
    final path = await _channel.invokeMethod<String>('getAppDocumentsPath');
    if (path == null || path.isEmpty) {
      throw StateError('Empty documents path from Android');
    }
    _documentsPath = path;
    return path;
  }

  Future<String> supportPath() async {
    if (!Platform.isAndroid) {
      return (await getApplicationSupportDirectory()).path;
    }
    if (_supportPath != null) {
      return _supportPath!;
    }
    final path = await _channel.invokeMethod<String>('getAppSupportPath');
    if (path == null || path.isEmpty) {
      throw StateError('Empty support path from Android');
    }
    _supportPath = path;
    return path;
  }

  Future<Directory> documentsDirectory() async {
    return Directory(await documentsPath());
  }

  Future<Directory> supportDirectory() async {
    return Directory(await supportPath());
  }

  Future<Directory> cacheDirectory() async {
    return Directory(await cachePath());
  }

  Future<Directory> temporaryDirectory() async {
    return cacheDirectory();
  }
}
