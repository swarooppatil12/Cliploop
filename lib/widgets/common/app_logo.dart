import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 28,
    this.borderRadius,
  });

  final double size;
  final double? borderRadius;

  static const _assetPath = 'assets/icon/app_icon.png';

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? size * 0.28;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: AppColors.surfaceBorder.withValues(alpha: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          _assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return ColoredBox(
              color: AppColors.surfaceElevated,
              child: Icon(
                Icons.music_note_rounded,
                size: size * 0.62,
                color: AppColors.primaryGreen,
              ),
            );
          },
        ),
      ),
    );
  }
}
