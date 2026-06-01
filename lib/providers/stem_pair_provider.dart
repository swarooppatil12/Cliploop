import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/file_helper.dart';
import '../models/stem_pair_result.dart';
import '../services/stem_pair_service.dart';

enum StemPairState { idle, analyzing, complete, error }

class StemPairProvider extends ChangeNotifier {
  StemPairProvider({StemPairService? service})
      : _service = service ?? StemPairService();

  final StemPairService _service;

  String? vocalPath;
  String? bgmPath;
  String? vocalFileName;
  String? bgmFileName;

  StemPairResult? result;
  StemPairState state = StemPairState.idle;
  String? errorMessage;

  bool get canAnalyze =>
      vocalPath != null &&
      bgmPath != null &&
      state != StemPairState.analyzing;

  Future<void> pickVocal() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'],
    );
    if (picked == null || picked.files.isEmpty) {
      return;
    }
    final file = picked.files.first;
    if (file.path == null) {
      return;
    }
    vocalPath = file.path;
    vocalFileName = file.name;
    result = null;
    state = StemPairState.idle;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> pickBgm() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'],
    );
    if (picked == null || picked.files.isEmpty) {
      return;
    }
    final file = picked.files.first;
    if (file.path == null) {
      return;
    }
    bgmPath = file.path;
    bgmFileName = file.name;
    result = null;
    state = StemPairState.idle;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> analyze() async {
    final vPath = vocalPath;
    final bPath = bgmPath;
    if (vPath == null || bPath == null) {
      return;
    }

    state = StemPairState.analyzing;
    errorMessage = null;
    notifyListeners();

    try {
      result = await _service.analyze(
        vocalPath: vPath,
        bgmPath: bPath,
        vocalFileName: vocalFileName ?? FileHelper.fileName(vPath),
        bgmFileName: bgmFileName ?? FileHelper.fileName(bPath),
      );
      state = StemPairState.complete;
    } catch (error) {
      state = StemPairState.error;
      errorMessage = error.toString();
      result = null;
    }
    notifyListeners();
  }

  void clear() {
    vocalPath = null;
    bgmPath = null;
    vocalFileName = null;
    bgmFileName = null;
    result = null;
    state = StemPairState.idle;
    errorMessage = null;
    notifyListeners();
  }
}
