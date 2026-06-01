import 'package:flutter/material.dart';

/// Bottom nav: 0 = Home, 1 = Method 2, 2 = Method 3.
/// Method 1 (Song Structure) opens from Home shortcuts only.
class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const spleeter = '/spleeter';
  static const whisper = '/whisper';
  static const stemInspector = '/method3';
  static const processing = '/processing';

  static void onBottomNavTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, home);
      case 1:
        Navigator.pushReplacementNamed(context, whisper);
      case 2:
        Navigator.pushReplacementNamed(context, stemInspector);
    }
  }
}
