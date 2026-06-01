import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/music_provider.dart';

class MethodShortcutRow extends StatelessWidget {
  const MethodShortcutRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: _ShortcutCard(
              title: 'Song Structure',
              subtitle: 'Method 1 · Prelude & interludes',
              icon: Icons.auto_awesome_rounded,
              accent: AppColors.primaryGreen,
              onTap: () => _openSongStructure(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ShortcutCard(
              title: 'Vocal Remover',
              subtitle: 'Method 2 · Acapella & karaoke',
              icon: Icons.mic_external_on_rounded,
              accent: AppColors.accentPink,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pushReplacementNamed(context, AppRoutes.whisper);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openSongStructure(BuildContext context) {
    HapticFeedback.selectionClick();
    final provider = context.read<MusicProvider>();
    if (provider.selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload or select a song first, then open Song Structure.'),
        ),
      );
      return;
    }

    Navigator.pushNamed(context, AppRoutes.spleeter);
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: AppTextStyles.headlineMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
