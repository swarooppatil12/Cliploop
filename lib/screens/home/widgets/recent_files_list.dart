import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/music_file.dart';
import '../../../providers/music_provider.dart';
import 'file_card.dart';

class RecentFilesList extends StatelessWidget {
  const RecentFilesList({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        final files = provider.recentFiles;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, compact ? 4 : 8, 20, compact ? 2 : 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Library',
                          style: compact
                              ? AppTextStyles.headlineLarge.copyWith(fontSize: 17)
                              : AppTextStyles.headlineLarge,
                        )
                            .animate()
                            .fadeIn(duration: 450.ms, curve: Curves.easeOutCubic)
                            .slideY(begin: 0.2, curve: Curves.easeOutCubic),
                        if (!compact)
                          Text(
                            'Stored on this device · tap to select · delete to remove',
                            style: AppTextStyles.bodyMedium.copyWith(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  if (files.isNotEmpty)
                    TextButton(
                      onPressed: () => _openLibrarySheet(context, files),
                      child: const Text('See all'),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: compact ? 120 : 148,
              child: files.isEmpty
                  ? const _EmptyLibrary()
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final file = files[index];
                        return FileCard(
                          file: file,
                          isSelected: provider.selectedFile?.id == file.id,
                          animationIndex: index,
                          onTap: () => _selectFile(context, file),
                          onDelete: () => _confirmDelete(context, file),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectFile(BuildContext context, MusicFile file) async {
    final isNewTrack = await context.read<MusicProvider>().loadFile(file);
    if (!context.mounted) {
      return;
    }

    if (isNewTrack) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected ${file.name}')),
      );
    }
  }

  Future<void> _openLibrarySheet(
    BuildContext context,
    List<MusicFile> files,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Consumer<MusicProvider>(
              builder: (context, provider, _) {
                final library = provider.recentFiles;
                return Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceBorder,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Text('My Library', style: AppTextStyles.headlineLarge),
                          const Spacer(),
                          Text(
                            '${library.length} file${library.length == 1 ? '' : 's'}',
                            style: AppTextStyles.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: library.isEmpty
                          ? const _EmptyLibrary()
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                              itemCount: library.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final file = library[index];
                                final selected =
                                    provider.selectedFile?.id == file.id;
                                return Dismissible(
                                  key: ValueKey(file.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentPink.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(Icons.delete_outline),
                                  ),
                                  confirmDismiss: (_) =>
                                      _confirmDelete(context, file),
                                  child: ListTile(
                                    onTap: () {
                                      Navigator.pop(context);
                                      unawaited(_selectFile(context, file));
                                    },
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: BorderSide(
                                        color: selected
                                            ? AppColors.primaryGreen
                                            : AppColors.surfaceBorder,
                                      ),
                                    ),
                                    tileColor: AppColors.surfaceElevated,
                                    leading: Icon(
                                      Icons.audiotrack_rounded,
                                      color: selected
                                          ? AppColors.primaryGreen
                                          : AppColors.textSecondary,
                                    ),
                                    title: Text(
                                      file.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      _subtitleFor(file),
                                      style: AppTextStyles.bodyMedium,
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        final removed =
                                            await _confirmDelete(context, file);
                                        if (removed == true && context.mounted) {
                                          if (provider.recentFiles.isEmpty) {
                                            Navigator.pop(context);
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  String _subtitleFor(MusicFile file) {
    final sizeMb = (file.fileSizeBytes / (1024 * 1024)).toStringAsFixed(1);
    return '${file.durationSeconds}s · $sizeMb MB · saved on device';
  }

  Future<bool?> _confirmDelete(BuildContext context, MusicFile file) async {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text('Delete from library?', style: AppTextStyles.headlineLarge),
          content: Text(
            '${file.name} will be removed from Cliploops and deleted from '
            'this device. Separated stems for this song will also be removed.',
            style: AppTextStyles.bodyLarge,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    ).then((confirmed) async {
      if (confirmed == true && context.mounted) {
        await context.read<MusicProvider>().removeRecentFile(file);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted ${file.name}')),
          );
        }
      }
      return confirmed;
    });
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 42,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: 10),
          Text('No saved tracks yet', style: AppTextStyles.bodyLarge),
          const SizedBox(height: 4),
          Text(
            'Upload a song above — it stays in your library on this phone',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
