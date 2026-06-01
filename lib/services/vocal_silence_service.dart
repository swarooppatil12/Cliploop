import 'dart:math' as math;
import 'dart:typed_data';

import '../core/constants/processing_constants.dart';

enum VocalSilenceLevel { silent, minimal, quiet }

class VocalSilenceRegion {
  const VocalSilenceRegion({
    required this.startSeconds,
    required this.endSeconds,
    required this.durationSeconds,
    required this.avgRms,
    required this.level,
    required this.percentOfSong,
  });

  final double startSeconds;
  final double endSeconds;
  final double durationSeconds;
  final double avgRms;
  final VocalSilenceLevel level;
  final double percentOfSong;
}

class VocalSilenceSummary {
  const VocalSilenceSummary({
    required this.regionCount,
    required this.totalQuietSeconds,
    required this.totalSilentSeconds,
    required this.percentQuiet,
    required this.percentStrictlySilent,
    required this.threshold,
    required this.regions,
  });

  final int regionCount;
  final double totalQuietSeconds;
  final double totalSilentSeconds;
  final double percentQuiet;
  final double percentStrictlySilent;
  final double threshold;
  final List<VocalSilenceRegion> regions;
}

/// Detects long quiet spans on an isolated vocal stem (Method 3 / visual inspector).
class VocalSilenceService {
  VocalSilenceService._();

  static VocalSilenceSummary analyze(
    Float32List vocalStem,
    int sampleRate,
    double songDuration,
  ) {
    final raw = _detectRegions(vocalStem, sampleRate);
    return _summarize(raw, songDuration);
  }

  static _SilenceRaw _detectRegions(Float32List vocalStem, int sampleRate) {
    if (vocalStem.isEmpty) {
      return _SilenceRaw(
        regions: const [],
        threshold: ProcessingConstants.vocalStemPresentThreshold,
      );
    }

    const frameLength = 2048;
    const hopLength = 512;
    final minDuration = ProcessingConstants.minVocalSilenceSeconds;
    final mergeGap = ProcessingConstants.vocalSilenceMergeGapSeconds;

    final rmsValues = <double>[];
    final frameStarts = <double>[];
    final frameEnds = <double>[];

    for (var start = 0; start + frameLength <= vocalStem.length; start += hopLength) {
      var sum = 0.0;
      for (var i = start; i < start + frameLength; i++) {
        sum += vocalStem[i] * vocalStem[i];
      }
      rmsValues.add(math.sqrt(sum / frameLength));
      frameStarts.add(start / sampleRate);
      frameEnds.add((start + frameLength) / sampleRate);
    }

    if (rmsValues.isEmpty) {
      return _SilenceRaw(
        regions: const [],
        threshold: ProcessingConstants.vocalStemPresentThreshold,
      );
    }

    final sorted = List<double>.from(rmsValues)..sort();
    final quietIndex = math.min(sorted.length - 1, (sorted.length * 0.2).floor());
    final midIndex = math.min(sorted.length - 1, (sorted.length * 0.5).floor());
    final quietRef = sorted[quietIndex];
    final midRef = sorted[midIndex];
    final adaptive =
        quietRef + (midRef - quietRef) * ProcessingConstants.vocalStemAdaptiveBlend;
    final threshold = math.max(ProcessingConstants.vocalStemPresentThreshold, adaptive);
    final minimalThreshold = ProcessingConstants.vocalStemMinimalThreshold;

    final rawRegions = <(double, double)>[];
    int? activeStart;

    for (var index = 0; index < rmsValues.length; index++) {
      final isQuiet = rmsValues[index] < threshold;
      if (isQuiet && activeStart == null) {
        activeStart = index;
      } else if (!isQuiet && activeStart != null) {
        final startSeconds = frameStarts[activeStart];
        final endSeconds = frameEnds[index - 1];
        if (endSeconds - startSeconds >= minDuration) {
          rawRegions.add((startSeconds, endSeconds));
        }
        activeStart = null;
      }
    }

    if (activeStart != null) {
      final startSeconds = frameStarts[activeStart];
      final endSeconds = frameEnds.last;
      if (endSeconds - startSeconds >= minDuration) {
        rawRegions.add((startSeconds, endSeconds));
      }
    }

    final merged = _mergeRegions(rawRegions, mergeGap);
    final regions = <VocalSilenceRegion>[];

    for (final (start, end) in merged) {
      final duration = end - start;
      if (duration < minDuration) {
        continue;
      }
      final avgRms = _averageRmsInRange(vocalStem, sampleRate, start, end);
      final level = avgRms < minimalThreshold
          ? VocalSilenceLevel.silent
          : avgRms < threshold
              ? VocalSilenceLevel.minimal
              : VocalSilenceLevel.quiet;
      regions.add(
        VocalSilenceRegion(
          startSeconds: _round3(start),
          endSeconds: _round3(end),
          durationSeconds: _round3(duration),
          avgRms: _round3(avgRms),
          level: level,
          percentOfSong: 0,
        ),
      );
    }

    return _SilenceRaw(regions: regions, threshold: _round3(threshold));
  }

  static VocalSilenceSummary _summarize(_SilenceRaw raw, double songDuration) {
    var totalQuiet = 0.0;
    var strictTotal = 0.0;
    final enriched = <VocalSilenceRegion>[];

    for (final region in raw.regions) {
      totalQuiet += region.durationSeconds;
      if (region.level == VocalSilenceLevel.silent) {
        strictTotal += region.durationSeconds;
      }
      enriched.add(
        VocalSilenceRegion(
          startSeconds: region.startSeconds,
          endSeconds: region.endSeconds,
          durationSeconds: region.durationSeconds,
          avgRms: region.avgRms,
          level: region.level,
          percentOfSong: songDuration > 0
              ? _round3(region.durationSeconds / songDuration * 100)
              : 0,
        ),
      );
    }

    return VocalSilenceSummary(
      regionCount: enriched.length,
      totalQuietSeconds: _round3(totalQuiet),
      totalSilentSeconds: _round3(strictTotal),
      percentQuiet:
          songDuration > 0 ? _round3(totalQuiet / songDuration * 100) : 0,
      percentStrictlySilent:
          songDuration > 0 ? _round3(strictTotal / songDuration * 100) : 0,
      threshold: raw.threshold,
      regions: enriched,
    );
  }

  static List<(double, double)> _mergeRegions(
    List<(double, double)> regions,
    double gap,
  ) {
    if (regions.isEmpty) {
      return [];
    }
    final sorted = List<(double, double)>.from(regions)
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(double, double)>[(sorted.first.$1, sorted.first.$2)];

    for (var i = 1; i < sorted.length; i++) {
      final (start, end) = sorted[i];
      final last = merged.last;
      if (start - last.$2 <= gap) {
        merged[merged.length - 1] = (last.$1, math.max(last.$2, end));
      } else {
        merged.add((start, end));
      }
    }
    return merged;
  }

  static double _averageRmsInRange(
    Float32List samples,
    int sampleRate,
    double start,
    double end,
  ) {
    final startSample = math.max(0, (start * sampleRate).floor());
    final endSample = math.min(samples.length, (end * sampleRate).floor());
    if (endSample <= startSample) {
      return 0;
    }
    var sum = 0.0;
    for (var i = startSample; i < endSample; i++) {
      sum += samples[i] * samples[i];
    }
    return math.sqrt(sum / (endSample - startSample));
  }

  static double _round3(double value) => (value * 1000).round() / 1000;
}

class _SilenceRaw {
  const _SilenceRaw({required this.regions, required this.threshold});

  final List<VocalSilenceRegion> regions;
  final double threshold;
}
