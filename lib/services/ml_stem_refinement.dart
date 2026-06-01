import 'dart:math' as math;
import 'dart:typed_data';

import '../core/constants/processing_constants.dart';

/// Aggressive post-processing for ML-separated acapella + karaoke stems.
class MlStemRefinement {
  MlStemRefinement._();

  /// Karaoke = mix − vocals (residual). Acapella = vocal stem with bleed removed.
  static TwoStemOutput refine({
    required Float32List left,
    required Float32List right,
    required Float32List vocalsLeft,
    required Float32List vocalsRight,
  }) {
    final length = math.min(
      math.min(left.length, right.length),
      math.min(vocalsLeft.length, vocalsRight.length),
    );

    final vocals = Float32List(length);
    final accompaniment = Float32List(length);
    final mid = Float32List(length);
    final side = Float32List(length);

    const vocalCancel = 1.38;

    for (var i = 0; i < length; i++) {
      mid[i] = (left[i] + right[i]) * 0.5;
      side[i] = (left[i] - right[i]) * 0.5;

      var vL = vocalsLeft[i];
      var vR = vocalsRight[i];
      vocals[i] = (vL + vR) * 0.5;

      var instL = left[i] - vL * vocalCancel;
      var instR = right[i] - vR * vocalCancel;
      accompaniment[i] = (instL + instR) * 0.5;
    }

    final harmonicGain = _hpssHarmonicGains(vocals, radius: 14);
    final percussiveGain = Float32List(length);
    for (var i = 0; i < length; i++) {
      percussiveGain[i] = (1.0 - harmonicGain[i]).clamp(0.0, 1.0);
    }

    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < length; i++) {
        final sideAbs = side[i].abs();
        final midAbs = mid[i].abs();
        final width = sideAbs / (midAbs + 1e-9);

        // Acapella: strip wide / percussive bleed (drums, panned instruments).
        if (width > 0.38 && percussiveGain[i] > 0.40) {
          vocals[i] *= 0.12;
        } else if (percussiveGain[i] > 0.62) {
          vocals[i] *= 0.35;
        }

        vocals[i] -= accompaniment[i] * 0.28 * percussiveGain[i];
        vocals[i] -= side[i] * 0.18 * percussiveGain[i];

        // Karaoke: cancel vocal harmonics again (residual = mix − vocals).
        final cancelStrength = 0.96 + 0.04 * harmonicGain[i];
        accompaniment[i] -= vocals[i] * cancelStrength;

        if (vocals[i].abs() > 0.012 && harmonicGain[i] > 0.40) {
          accompaniment[i] -= vocals[i] * 0.28;
        }

        vocals[i] = vocals[i].clamp(-1.0, 1.0);
        accompaniment[i] = accompaniment[i].clamp(-1.0, 1.0);
      }
    }

    _highPassInPlace(
      vocals,
      cutoffHz: ProcessingConstants.dspVocalHighPassHz,
      sampleRate: ProcessingConstants.defaultSampleRate,
    );

    _normalizeInPlace(vocals);
    _normalizeInPlace(accompaniment);

    return TwoStemOutput(vocals: vocals, accompaniment: accompaniment);
  }

  static void _highPassInPlace(
    Float32List samples, {
    required double cutoffHz,
    required int sampleRate,
  }) {
    if (samples.isEmpty) {
      return;
    }
    final rc = 1.0 / (2 * math.pi * cutoffHz);
    final dt = 1.0 / sampleRate;
    final alpha = rc / (rc + dt);
    var prevIn = samples[0];
    var prevOut = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final x = samples[i];
      final y = alpha * (prevOut + x - prevIn);
      prevIn = x;
      prevOut = y;
      samples[i] = y;
    }
  }

  static Float32List _hpssHarmonicGains(
    Float32List mono, {
    int radius = 12,
  }) {
    const frameLength = 2048;
    const hopLength = 512;
    final frameCount = math.max(
      1,
      (mono.length - frameLength) ~/ hopLength + 1,
    );
    final frameEnergy = List<double>.filled(frameCount, 0);
    for (var f = 0; f < frameCount; f++) {
      final start = f * hopLength;
      if (start + frameLength > mono.length) {
        break;
      }
      var sum = 0.0;
      for (var i = start; i < start + frameLength; i++) {
        sum += mono[i] * mono[i];
      }
      frameEnergy[f] = math.sqrt(sum / frameLength);
    }

    final harmonic = _movingAverage(frameEnergy, radius: radius);
    final gains = Float32List(mono.length);

    for (var i = 0; i < mono.length; i++) {
      final frameIndex =
          (i / hopLength).floor().clamp(0, frameCount - 1);
      final total = frameEnergy[frameIndex];
      final slow = harmonic[frameIndex];
      gains[i] = total > 1e-9 ? (slow / total).clamp(0.0, 1.0) : 0.5;
    }

    return gains;
  }

  static List<double> _movingAverage(List<double> values, {required int radius}) {
    if (values.isEmpty) {
      return [];
    }
    final out = List<double>.filled(values.length, 0);
    for (var i = 0; i < values.length; i++) {
      final start = math.max(0, i - radius);
      final end = math.min(values.length, i + radius + 1);
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        sum += values[j];
      }
      out[i] = sum / (end - start);
    }
    return out;
  }

  static void _normalizeInPlace(Float32List samples) {
    var peak = 0.0;
    for (final value in samples) {
      peak = math.max(peak, value.abs());
    }
    if (peak < 1e-9) {
      return;
    }
    final scale = 0.95 / peak;
    for (var i = 0; i < samples.length; i++) {
      samples[i] *= scale;
    }
  }
}

/// Vocals + instrumental output pair.
class TwoStemOutput {
  const TwoStemOutput({
    required this.vocals,
    required this.accompaniment,
  });

  final Float32List vocals;
  final Float32List accompaniment;
}
