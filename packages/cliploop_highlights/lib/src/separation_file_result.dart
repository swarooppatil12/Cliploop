/// Result of streaming separation — stem files on disk, no full PCM in RAM.
class SeparationFileResult {
  const SeparationFileResult({
    required this.vocalsPath,
    required this.accompanimentPath,
    required this.sampleRate,
    required this.frameCount,
  });

  final String vocalsPath;
  final String accompanimentPath;
  final int sampleRate;
  final int frameCount;

  double get durationSeconds =>
      sampleRate == 0 ? 0 : frameCount / sampleRate;
}
