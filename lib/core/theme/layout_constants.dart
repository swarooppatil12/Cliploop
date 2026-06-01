import 'package:flutter/material.dart';

/// Shared spacing and padding for mobile screens (iOS + Android).
class AppLayout {
  AppLayout._();

  static const pageHorizontal = 20.0;
  static const pageTop = 8.0;
  static const pageBottom = 24.0;
  static const sectionGap = 20.0;
  static const cardRadius = 16.0;

  static EdgeInsets pagePadding({double bottom = pageBottom}) {
    return EdgeInsets.fromLTRB(pageHorizontal, pageTop, pageHorizontal, bottom);
  }
}
