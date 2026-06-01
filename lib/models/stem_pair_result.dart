import 'segment.dart';
import 'vocal_model_output.dart';
import '../services/vocal_silence_service.dart';

/// Result of Method 3 stem-pair analysis (uploaded vocal + instrumental).
class StemPairResult {
  const StemPairResult({
    required this.vocalFileName,
    required this.bgmFileName,
    required this.vocalStemPath,
    required this.bgmStemPath,
    required this.sampleRate,
    required this.durationSeconds,
    required this.warnings,
    required this.structureSegments,
    required this.vocalModelOutput,
    required this.vocalSilence,
    required this.vocalWaveform,
    required this.bgmWaveform,
    required this.processedAt,
  });

  final String vocalFileName;
  final String bgmFileName;
  final String vocalStemPath;
  final String bgmStemPath;
  final int sampleRate;
  final double durationSeconds;
  final List<String> warnings;
  final List<Segment> structureSegments;
  final VocalModelOutput vocalModelOutput;
  final VocalSilenceSummary vocalSilence;
  final List<double> vocalWaveform;
  final List<double> bgmWaveform;
  final DateTime processedAt;
}
