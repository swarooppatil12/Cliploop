import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';

class StructureLegend extends StatelessWidget {
  const StructureLegend({super.key});

  static const _items = [
    (Color(0xFF22C55E), 'Vocal regions'),
    (Color(0xFF38BDF8), 'Structure blocks'),
    (Color(0xFFA78BFA), 'Interlude candidates'),
    (AppColors.segmentPrelude, 'Prelude'),
    (AppColors.segmentInterlude, 'Interlude'),
    (AppColors.segmentPostlude, 'Postlude'),
    (Color(0xFFEF4444), 'Vocal silent'),
    (Color(0xFFFB923C), 'Vocal minimal'),
    (AppColors.stemVocals, 'Vocal stem'),
    (AppColors.stemAccompaniment, 'Instrumental stem'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: _items
          .map(
            (item) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: item.$1,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  item.$2,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}
