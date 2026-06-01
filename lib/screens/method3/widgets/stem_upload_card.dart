import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';

class StemUploadCard extends StatelessWidget {
  const StemUploadCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.fileName,
    required this.borderColor,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String? fileName;
  final Color borderColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasFile = fileName != null && fileName!.isNotEmpty;

    return Expanded(
      child: Material(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasFile ? borderColor : AppColors.surfaceBorder,
                width: hasFile ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: borderColor, size: 28),
                const SizedBox(height: 10),
                Text(title, style: AppTextStyles.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  hasFile ? fileName! : subtitle,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: hasFile
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
