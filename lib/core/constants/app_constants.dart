class AppConstants {
  AppConstants._();

  static const String appName = 'Swaroop App';
  static const String recentFilesCacheFile = 'recent_files.json';
  static const String selectedFileCacheFile = 'selected_file.json';
  static const String tracksCacheDir = 'tracks';
  static const String stemsCacheDir = 'stems';
  static const String downloadsSubDir = 'SwaroopApp';
  static const int waveformSampleCount = 120;
  static const int pollIntervalSeconds = 3;
  static const List<String> supportedAudioExtensions = [
    'mp3',
    'wav',
    'm4a',
    'aac',
    'flac',
    'ogg',
  ];
}
