import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
          child: Row(
            children: [
              _NavItem(
                label: 'Home',
                shortLabel: 'Home',
                icon: Icons.home_rounded,
                activeColor: AppColors.primaryPurple,
                isActive: currentIndex == 0,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap(0);
                },
              ),
              _NavItem(
                label: 'Vocals',
                shortLabel: 'M2',
                icon: Icons.mic_external_on_rounded,
                activeColor: AppColors.accentPink,
                isActive: currentIndex == 1,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap(1);
                },
              ),
              _NavItem(
                label: 'Stems',
                shortLabel: 'M3',
                icon: Icons.upload_file_rounded,
                activeColor: AppColors.accentOrange,
                isActive: currentIndex == 2,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap(2);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.activeColor,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final String shortLabel;
  final IconData icon;
  final Color activeColor;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final useShortLabel = MediaQuery.sizeOf(context).width < 360;
    final displayLabel = useShortLabel ? shortLabel : label;
    final color = isActive ? activeColor : AppColors.textSecondary;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 3),
                Text(
                  displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isActive
                      ? AppTextStyles.bodyMedium.copyWith(
                          color: activeColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        )
                      : AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
