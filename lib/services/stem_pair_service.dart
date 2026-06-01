import '../models/segment.dart';
import '../models/stem_pair_result.dart';
import 'local_audio_engine.dart';

/// Method 3 — stem pair structure analysis (no separation).
class StemPairService {
  StemPairService({LocalAudioEngine? engine})
      : _engine = engine ?? LocalAudioEngine();

  final LocalAudioEngine _engine;

  Future<StemPairResult> analyze({
    required String vocalPath,
    required String bgmPath,
    required String vocalFileName,
    required String bgmFileName,
  }) {
    return _engine.analyzeStemPair(
      vocalPath: vocalPath,
      bgmPath: bgmPath,
      vocalFileName: vocalFileName,
      bgmFileName: bgmFileName,
    );
  }

  Future<GaplessMixExport> exportGaplessMix({
    required String vocalStemPath,
    required String bgmStemPath,
    required List<Segment> structureSegments,
    int crossfadeMs = 80,
  }) {
    return _engine.exportGaplessMixWav(
      inputPath: vocalStemPath,
      structureSegments: structureSegments,
      vocalsStemPath: vocalStemPath,
      drumsStemPath: bgmStemPath,
      crossfadeMs: crossfadeMs,
    );
  }
}
