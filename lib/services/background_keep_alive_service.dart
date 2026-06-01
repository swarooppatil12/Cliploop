import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the device awake during long on-device ML jobs.
///
/// We intentionally avoid configuring a second [AudioPlayer] here — on iOS that
/// deadlocks with stem preview/playback in [AudioPlayerService].
class BackgroundKeepAliveService {
  BackgroundKeepAliveService._();

  static final BackgroundKeepAliveService instance =
      BackgroundKeepAliveService._();

  int _holdCount = 0;
  bool _active = false;

  Future<void> acquire() async {
    _holdCount++;
    if (_active) {
      return;
    }
    _active = true;

    try {
      await WakelockPlus.enable().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      debugPrint('Wakelock enable timed out — continuing without it.');
    } catch (error, stackTrace) {
      debugPrint('Wakelock enable failed: $error\n$stackTrace');
    }
  }

  Future<void> release() async {
    if (_holdCount <= 0) {
      return;
    }
    _holdCount--;
    if (_holdCount > 0 || !_active) {
      return;
    }
    _active = false;

    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}
