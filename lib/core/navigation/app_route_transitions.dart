import 'package:flutter/material.dart';

import '../../screens/home/home_screen.dart';
import '../../screens/method1/spleeter_screen.dart';
import '../../screens/method2/whisper_screen.dart';
import '../../screens/method3/stem_inspector_screen.dart';
import '../../screens/shared/processing_screen.dart';
import 'app_routes.dart';

/// Shared route transition used across Cliploops screens.
Route<T> buildAnimatedRoute<T>({
  required RouteSettings settings,
  required Widget page,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Route<dynamic>? generateAppRoute(RouteSettings settings) {
  switch (settings.name) {
    case AppRoutes.home:
      return buildAnimatedRoute(
        settings: settings,
        page: const HomeScreen(),
      );
    case AppRoutes.spleeter:
      return buildAnimatedRoute(
        settings: settings,
        page: const SpleeterScreen(),
      );
    case AppRoutes.whisper:
      return buildAnimatedRoute(
        settings: settings,
        page: const WhisperScreen(),
      );
    case AppRoutes.stemInspector:
      return buildAnimatedRoute(
        settings: settings,
        page: const StemInspectorScreen(),
      );
    case AppRoutes.processing:
      return buildAnimatedRoute(
        settings: settings,
        page: ProcessingScreen(
          method: ProcessingScreen.methodFromArgs(settings.arguments),
        ),
      );
    default:
      return null;
  }
}
