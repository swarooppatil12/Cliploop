class ProcessingConstants {
  ProcessingConstants._();

  /// Maximum time allowed for on-device processing of a single file.
  static const int timeoutSeconds = 600;

  static const int defaultSampleRate = 44100;
  static const int waveformPoints = 120;

  /// HT-Demucs ONNX tuned for on-device mobile inference.
  static const int demucsSampleRate = 44100;
  static const double demucsSegmentSeconds = 7.8;
  static const int demucsSegmentSamples = 343980;

  /// ONNX thread counts — conservative for mobile thermals / battery.
  static const int demucsIntraOpThreads = 2;
  static const int demucsInterOpThreads = 1;

  /// Chunk overlap inside each Demucs segment (smaller = fewer passes, faster).
  static const double demucsOverlapFraction = 0.125;

  /// Smaller windows on iOS to keep Demucs ONNX peak RAM low.
  static const int demucsIosWindowSamples = 44100 * 22;
  static const int demucsIosWindowOverlap = 44100 * 2;

  /// Android / desktop file streaming window size.
  static const int demucsMobileWindowSamples = 44100 * 45;
  static const int demucsMobileWindowOverlap = 44100 * 2;

  /// Only 2 stems: isolated vocals + instrumental (everything else).
  static const List<String> twoStems = ['vocals', 'accompaniment'];

  static const String defaultSeparationModel = 'uvr-mdxnet-9482';

  static const Map<String, List<String>> stemSets = {
    'demucs-2stems': twoStems,
    // Legacy ids from older builds — all resolve to vocals + instrumental.
    'demucs-mobile': twoStems,
    'spleeter-2stems': twoStems,
    'spleeter-4stems': twoStems,
    'spleeter-5stems': twoStems,
    'demucs-4stems': twoStems,
  };

  static const Map<String, String> separationModelLabels = {
    'demucs-2stems': 'Vocals + Instrumental',
    'demucs-mobile': 'Vocals + Instrumental',
    'spleeter-2stems': 'Vocals + Instrumental',
    'spleeter-2stems-fp16': 'Vocals + Instrumental (Spleeter ML)',
    'uvr-mdxnet-9482': 'Vocals + Instrumental (UVR ML)',
    'spleeter-4stems': 'Vocals + Instrumental',
    'spleeter-5stems': 'Vocals + Instrumental',
    'demucs-4stems': 'Vocals + Instrumental',
  };

  /// Always returns the 2-stem set regardless of saved model id.
  static List<String> resolveStemNames(String? model) {
    return List<String>.from(twoStems);
  }

  /// Method 2 — SVAD only (Silero Voice Activity Detection on separated vocals).
  static const Map<String, String> method2VocalModels = {
    'silero-vad': 'SVAD',
  };

  static const String defaultMethod2VocalModel = 'silero-vad';

  static const String sileroVadModelId = 'silero-vad';

  /// User-facing label for Method 2 voice detection (not generic "VAD").
  static const String svadModelLabel = 'SVAD';

  /// If Silero labels less than this fraction of the song as vocal, use stem energy.
  static const double minVadCoverageFraction = 0.06;

  /// Only merge energy detections into SVAD when energy coverage exceeds VAD by this factor.
  static const double vadEnergyMergeMaxRatio = 1.35;

  /// On the full mix — legacy fallback only.
  static const double vocalEnergyThreshold = 0.02;

  /// Frames between this and [vocalEnergyThreshold] are vocal-minimal.
  static const double vocalMinimalEnergyThreshold = 0.008;

  /// On the isolated vocals stem — floor for vocal-present (high sensitivity).
  static const double vocalStemPresentThreshold = 0.002;

  /// On the vocals stem, below this = vocal-less; up to [vocalStemPresentThreshold] = minimal.
  static const double vocalStemMinimalThreshold = 0.0006;

  /// Hysteresis off-threshold as a fraction of the on-threshold (reduces bleed flicker).
  static const double vocalStemHysteresisRatio = 0.62;

  /// Consecutive vocal frames required to start a region (~70 ms at 44.1 kHz / 512 hop).
  static const int vocalOnsetMinFrames = 3;

  /// Consecutive non-vocal frames required to end a region.
  static const int vocalOffsetMinFrames = 5;

  /// Frame counts as vocal only when vocal RMS / instrumental RMS exceeds this.
  static const double vocalToInstrumentalMinRatio = 0.38;

  /// Energy-only region must exceed this mean vocal RMS to supplement SVAD.
  static const double vocalConfirmationMinEnergy = 0.003;

  /// Energy-only region must exceed this vocal/instrumental ratio to supplement SVAD.
  static const double vocalConfirmationMinRatio = 0.45;

  /// How far above the quiet reference (20th pct) the adaptive threshold sits (0–1).
  /// Lower = more sensitive. Was effectively ~0.3 toward peak (loud-only).
  static const double vocalStemAdaptiveBlend = 0.12;

  /// Shortest sustained vocal frame group to count as a vocal region.
  static const double minVocalRegionSeconds = 0.25;

  /// SVAD blips shorter than this are dropped unless vocal energy is very clear.
  static const double minConfirmedVocalRegionSeconds = 1.0;

  /// Unconditionally drop detected vocal regions shorter than this (UVR bleed).
  static const double maxBleedVocalRegionSeconds = 0.65;

  /// Fraction of vocal-active frames required to keep a short (0.25–0.85s) blip.
  static const double shortVocalBlipMinFrameFraction = 0.48;

  /// First span must be at least this long to end prelude (ignores UVR bleed before singing).
  static const double preludeEndMinVocalSpanSeconds = 4.0;

  /// Max prelude length when no clear opening instrumental span exists (seconds).
  static const double preludeMaxSeconds = 55.0;

  /// Opening non-vocal span must be at least this long to define prelude (seconds).
  static const double preludeOpeningMinSeconds = 8.0;

  /// Primary Silero threshold — singing, not stem bleed in instrumentals.
  static const double sileroVadPrimaryThreshold = 0.30;

  /// Secondary Silero pass when primary coverage is low (soft vocals).
  static const double sileroVadSecondaryThreshold = 0.20;

  /// Merge vocal frames separated by gaps shorter than this (seconds).
  static const double vocalRegionMergeGapSeconds = 0.55;

  /// Step 4 only — merge nearby detections into sung "blocks" (film songs).
  static const double structureVocalMergeGapSeconds = 4.5;

  /// Second pass merge for long film-song vocal blocks.
  static const double structureVocalSecondMergeGapSeconds = 8.0;

  /// Ignore blips shorter than this when building structure blocks.
  static const double structureMicroVocalMaxSeconds = 4.0;

  /// Intro adlibs before this time must be at least this long to form a sung block.
  static const double introAdlibMaxStartSeconds = 28.0;

  static const double introAdlibMinBlockSeconds = 8.0;

  /// Use full block gap as interlude when best carved span is below this fraction.
  static const double interludeMinCarvedSpanFraction = 0.65;

  /// Gaps between structure blocks must be at least this long to be an interlude.
  static const double minStructureInterludeSeconds = 6.0;

  /// Main singing usually starts after this point (long instrumental intros).
  static const double structurePreludeMinStartSeconds = 28.0;

  /// Minimum duration for a block to count as "main" singing start.
  static const double structureMainVocalMinBlockSeconds = 5.0;

  /// Minimum duration for a gap to qualify as Prelude / Interlude / Postlude.
  static const double minStructureGapSeconds = 1.5;

  /// Shorter minimum for drum-break interludes sandwiched in the song.
  static const double minInterludeGapSeconds = 1.0;

  /// Minimum gap inside a sung block to count as interlude (filters 00:52-style blips).
  static const double minIntraBlockInterludeSeconds = 8.0;

  /// How close to song start/end a gap must be to count as Prelude / Postlude.
  static const double structureEdgeToleranceSeconds = 0.5;

  /// Merge adjacent instrumental/interlude regions separated by gaps shorter than this.
  static const double instrumentalRegionMergeGapSeconds = 1.5;

  /// Max fraction of vocal-active frames allowed in an instrumental-only section.
  static const double instrumentalMaxVocalFrameFraction = 0.12;

  /// Relaxed frame fraction for structural gaps between sung blocks (UVR bleed).
  static const double structuralGapMaxVocalFrameFraction = 0.22;

  /// Mean vocal RMS must stay below this for instrumental-only validation.
  static const double instrumentalMaxVocalEnergy = 0.0018;

  /// Relaxed mean vocal RMS for structural gaps with active music.
  static const double structuralGapMaxVocalEnergy = 0.0045;

  /// Instrumental stem must exceed this mean RMS for music-driven sections.
  static const double instrumentalMinMusicEnergy = 0.0008;

  /// Vocal/instrumental energy ratio must stay below this for instrumental sections.
  static const double instrumentalMaxVocalToMusicRatio = 0.40;

  /// Relaxed vocal/instrumental ratio for structural gaps (separated-stem bleed).
  static const double structuralGapMaxVocalToMusicRatio = 0.72;

  /// Lightly merge raw vocal spans before interlude gap detection.
  static const double interludeRawBridgeMergeSeconds = 2.5;

  /// Merge interlude gap sources within this gap.
  static const double interludeSourceMergeGapSeconds = 2.0;

  /// Tolerance when matching a gap to a block boundary.
  static const double structureBlockGapToleranceSeconds = 1.0;

  /// Max lookback when refining interlude start to last raw vocal end.
  static const double interludeRefineStartMaxLookbackSeconds = 45.0;

  /// Max lookahead when refining interlude end to next raw vocal start.
  static const double interludeRefineEndMaxLookaheadSeconds = 25.0;

  /// Minimum RMS on the instrumental stem for a section to count as beats-driven.
  static const double interludeDrumsMinEnergy = 0.001;

  /// Instrumental energy must exceed vocal energy by this factor in a borderline interlude.
  static const double interludeDrumsToVocalRatio = 1.2;

  /// Method 3 — vocal silence regions (visual inspector parity).
  static const double minVocalSilenceSeconds = 10.0;
  static const double vocalSilenceMergeGapSeconds = 0.55;

  /// Karaoke / acapella stereo isolation tuning (iOS fallback — no Demucs).
  static const double dspSideBleedReject = 0.20;
  static const double dspVocalCancelStrength = 1.18;
  static const double dspSideInstrumentalBlend = 0.28;
  static const double dspVocalHighPassHz = 100;
  static const double dspNonVocalGateThreshold = 0.32;

  /// Primary on-device separation model (Android + iOS).
  static const String mobileSeparationModelId = 'uvr-mdxnet-9482';

  static const String mobileSeparationModelLabel = 'UVR vocal remover (ML)';

  /// Dart UVR ONNX threads (mobile streaming path).
  static const int uvrDartIntraOpThreads = 4;

  /// Android — more threads + larger windows for sub-minute full-song runs.
  static const int uvrAndroidIntraOpThreads = 6;
  static const int uvrAndroidOuterChunkSeconds = 45;
  static const int uvrAndroidOuterOverlapSeconds = 1;

  /// Native sherpa-onnx UVR thread count (when native path is used).
  static const int uvrNativeNumThreads = 4;

  /// Snapdragon — more threads + QNN (Qualcomm AI Engine Direct / Hexagon HTP).
  static const int uvrSnapdragonNativeThreads = 8;

  /// Target max separation time on Snapdragon Android (full song).
  static const int androidSeparationTargetSeconds = 60;

  /// Provider try-order on Snapdragon: QNN → XNNPACK → CPU.
  /// QNN replaces legacy NNAPI for direct Hexagon NPU access (SM8350+).
  static const List<String> uvrSnapdragonProviderChain = [
    'qnn',
    'xnnpack',
    'cpu',
  ];

  /// Provider try-order on other Android devices.
  static const List<String> uvrAndroidProviderChain = [
    'xnnpack',
    'cpu',
  ];

  /// Prefer Core ML for UVR on iOS (Neural Engine — much faster than CPU).
  static const bool uvrDartPreferCpuOnIos = false;

  /// Use Core ML execution provider when available on iOS.
  static const bool uvrDartUseCoreMlOnIos = true;

  /// Structure analysis uses mix_mono − vocal_mono (not the separated inst file)
  /// so vocal/instrumental ratios stay correct regardless of stem normalization.
  static const bool structureUseMixMinusVocal = true;

  /// Outer window + overlap (seconds) — overlap stitching preserves SVAD quality.
  static const int uvrOuterChunkSeconds = 30;
  static const int uvrOuterOverlapSeconds = 2;

  /// UVR MDXNET_9482 ONNX tensor layout (sherpa-onnx reference).
  static const int uvrMdxnetDimC = 4;
  static const int uvrMdxnetDimF = 2048;
  static const int uvrMdxnetDimT = 256;
  static const int uvrMdxnetNFft = 4096;
  static const int uvrMdxnetHopLength = 1024;
}
