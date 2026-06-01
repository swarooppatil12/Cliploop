import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/music_provider.dart';
import 'providers/player_provider.dart';
import 'providers/stem_pair_provider.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    GoogleFonts.config.allowRuntimeFetching = false;
  }

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error: $error\n$stack');
    return true;
  };

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MusicProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => StemPairProvider()),
      ],
      child: const CliploopsApp(),
    ),
  );

  // Defer non-critical startup work so the Flutter engine and VM service
  // become available immediately (critical for iOS device debug attach).
  unawaited(_deferredStartup());
}

Future<void> _deferredStartup() async {
  try {
    await NotificationService().initialize();
  } catch (error, stackTrace) {
    debugPrint('NotificationService init failed: $error\n$stackTrace');
  }
}
