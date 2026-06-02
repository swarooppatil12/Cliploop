import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/music_provider.dart';
import '../../services/share_intent_service.dart';

/// Defers disk bootstrap until after the first rasterized frame (Android safe).
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    required this.child,
    this.onReady,
  });

  final Widget child;
  final Future<void> Function()? onReady;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  @override
  void initState() {
    super.initState();
    // Do NOT use addPostFrameCallback here — it runs during the warm-up frame on
    // Android and races with HomeScreen. Schedule after first rasterized frame.
    unawaited(_deferredBootstrap());
  }

  Future<void> _deferredBootstrap() async {
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;

    if (Platform.isAndroid) {
      // Extra margin for Activity + JNI attach on Samsung / Android 16.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    if (!mounted) {
      return;
    }

    final music = context.read<MusicProvider>();
    await music.ensureBootstrapped();

    if (!mounted) {
      return;
    }

    ShareIntentService.instance.initialize(music);

    final onReady = widget.onReady;
    if (onReady != null) {
      await onReady();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
