import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android hardware profile — used to pick NNAPI / Hexagon (Snapdragon NPU) paths.
class AndroidDeviceProfile {
  const AndroidDeviceProfile({
    required this.isSnapdragon,
    required this.socModel,
    required this.hardware,
    required this.board,
  });

  final bool isSnapdragon;
  final String socModel;
  final String hardware;
  final String board;

  static const AndroidDeviceProfile nonAndroid = AndroidDeviceProfile(
    isSnapdragon: false,
    socModel: '',
    hardware: '',
    board: '',
  );

  @override
  String toString() =>
      'AndroidDeviceProfile(snapdragon=$isSnapdragon soc=$socModel hw=$hardware)';
}

/// Reads SoC info from Android native layer.
class AndroidDeviceService {
  AndroidDeviceService._();

  static final AndroidDeviceService instance = AndroidDeviceService._();

  static const MethodChannel _channel = MethodChannel('com.swaroop.app/device');

  AndroidDeviceProfile? _cached;

  Future<AndroidDeviceProfile> getProfile() async {
    if (!Platform.isAndroid) {
      return AndroidDeviceProfile.nonAndroid;
    }
    if (_cached != null) {
      return _cached!;
    }

    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getDeviceProfile',
      );
      if (raw == null) {
        _cached = AndroidDeviceProfile.nonAndroid;
        return _cached!;
      }

      _cached = AndroidDeviceProfile(
        isSnapdragon: raw['isSnapdragon'] == true,
        socModel: raw['socModel']?.toString() ?? '',
        hardware: raw['hardware']?.toString() ?? '',
        board: raw['board']?.toString() ?? '',
      );

      if (kDebugMode) {
        debugPrint('[Device] $_cached');
      }
      return _cached!;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Device] profile unavailable: $error');
      }
      _cached = AndroidDeviceProfile.nonAndroid;
      return _cached!;
    }
  }

  void clearCache() => _cached = null;
}
