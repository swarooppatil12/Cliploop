import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../core/utils/file_helper.dart';
import '../providers/music_provider.dart';
import 'notification_service.dart';

/// Handles audio files shared from WhatsApp, email, or the file manager.
class ShareIntentService with WidgetsBindingObserver {
  ShareIntentService._();

  static final ShareIntentService instance = ShareIntentService._();

  StreamSubscription<List<SharedMediaFile>>? _sharingSubscription;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _initialized = false;
  MusicProvider? _musicProvider;

  bool get isInForeground => _lifecycleState == AppLifecycleState.resumed;

  void initialize(MusicProvider musicProvider) {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _musicProvider = musicProvider;

    WidgetsBinding.instance.addObserver(this);

    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isEmpty) {
        return;
      }
      unawaited(_handleSharedFiles(files, fromColdStart: true));
      ReceiveSharingIntent.instance.reset();
    });

    _sharingSubscription =
        ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isEmpty) {
        return;
      }
      unawaited(_handleSharedFiles(files, fromColdStart: false));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  Future<void> _handleSharedFiles(
    List<SharedMediaFile> files, {
    required bool fromColdStart,
  }) async {
    final provider = _musicProvider;
    if (provider == null) {
      return;
    }

    final path = files.first.path;
    if (path.isEmpty) {
      return;
    }

    final fileName = FileHelper.fileName(path);

    try {
      await provider.loadFileFromPath(path);
    } catch (_) {
      return;
    }

    if (fromColdStart || isInForeground) {
      return;
    }

    NotificationService().showSharedFileReceived(fileName);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sharingSubscription?.cancel();
    _sharingSubscription = null;
    _musicProvider = null;
    _initialized = false;
  }
}
