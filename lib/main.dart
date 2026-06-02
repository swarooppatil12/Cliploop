import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/music_provider.dart';
import 'providers/player_provider.dart';
import 'providers/stem_pair_provider.dart';
import 'services/notification_service.dart';
import 'widgets/common/app_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Avoid blocking first frame on network font downloads (device debug attach).
  GoogleFonts.config.allowRuntimeFetching = false;

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
      child: AppBootstrap(
        onReady: _initializeNotifications,
        child: const CliploopsApp(),
      ),
    ),
  );
}

Future<void> _initializeNotifications() async {
  try {
    await NotificationService().initialize();
  } catch (error, stackTrace) {
    debugPrint('NotificationService init failed: $error\n$stackTrace');
  }
}
