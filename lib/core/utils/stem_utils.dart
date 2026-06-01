import 'package:flutter/material.dart';

import '../../models/track_stem.dart';
import '../constants/processing_constants.dart';
import '../theme/colors.dart';

class StemUtils {
  StemUtils._();

  static Color colorFor(StemType type) {
    switch (type) {
      case StemType.vocals:
        return AppColors.stemVocals;
      case StemType.accompaniment:
        return AppColors.stemAccompaniment;
      case StemType.drums:
        return AppColors.stemDrums;
      case StemType.bass:
        return AppColors.stemBass;
      case StemType.other:
        return AppColors.stemOther;
      case StemType.piano:
        return AppColors.stemPiano;
      case StemType.guitar:
        return AppColors.stemGuitar;
    }
  }

  static IconData iconFor(StemType type) {
    switch (type) {
      case StemType.vocals:
        return Icons.mic_rounded;
      case StemType.accompaniment:
        return Icons.music_note_rounded;
      case StemType.drums:
        return Icons.album_rounded;
      case StemType.bass:
        return Icons.music_note_rounded;
      case StemType.other:
        return Icons.queue_music_rounded;
      case StemType.piano:
        return Icons.piano_rounded;
      case StemType.guitar:
        return Icons.speaker_rounded;
    }
  }

  static String labelFor(StemType type) {
    switch (type) {
      case StemType.vocals:
        return 'Vocals';
      case StemType.accompaniment:
        return 'Instrumental';
      case StemType.drums:
        return 'Drums';
      case StemType.bass:
        return 'Bass';
      case StemType.other:
        return 'Other';
      case StemType.piano:
        return 'Piano';
      case StemType.guitar:
        return 'Guitar';
    }
  }

  static String modelLabel(String model) {
    return ProcessingConstants.separationModelLabels[model] ??
        'Vocals + Instrumental';
  }
}
