import 'package:flutter/material.dart';

import 'app_routes.dart';

class AppNavigator {
  AppNavigator._();

  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  static void openHome() {
    key.currentState?.pushNamedAndRemoveUntil(
      AppRoutes.home,
      (route) => false,
    );
  }

  static void openRoute(String routeName) {
    key.currentState?.pushNamedAndRemoveUntil(
      routeName,
      (route) => false,
    );
  }
}
