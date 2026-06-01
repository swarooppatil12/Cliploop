import 'dart:math' as math;
import 'dart:typed_data';

import '../core/constants/processing_constants.dart';

/// Isolated vocal (and optional drums) stems for Method 2 structure analysis.
class Method2Stems {
  const Method2Stems({
    required this.vocals,
    required this.drums,
  });

  final Float32List vocals;
  final Float32List drums;
}

/// Vocals + instrumental (mix − vocals) for 2-stem export.
class TwoStemOutput {
  const TwoStemOutput({
    required this.vocals,
    required this.accompaniment,
  });

  final Float32List vocals;
  final Float32List accompaniment;
}

/// On-device vocal isolation for Method 2 when ML (UVR) is unavailable.
class VocalSeparationEngine {
  VocalSeparationEngine._();

  static Method2Stems separate({
    required Float32List left,
    required Float32List right,
    required String model,
  }) {
    final id = ProcessingConstants.method2VocalModels.containsKey(model)
        ? model
        : ProcessingConstants.defaultMethod2VocalModel;

    switch (id) {
      case 'legacy-left':
        return _legacyLeft(left, right);
      case 'center-cancel':
        return _centerCancel(left, right);
      case 'hpss-harmonic':
        return _hpssLite(left, right);
      case 'mid-side':
      default:
        return _midSide(left, right);
    }
  }

  /// iOS / fallback vocal remover — center extraction, HPSS harmonics, mix-minus.
  static TwoStemOutput separateStems({
    required Float32List left,
    required Float32List right,
  }) {
    return separateForVocalRemover(left: left, right: right);
  }

  /// Two-pass stereo isolation tuned for clean acapella + karaoke export.
  ///
  /// Pass 1 — harmonic vocal estimate, side-channel instrumental base, mix-minus.
  /// Pass 2 — subtract cross-bleed so acapella loses drums/bass and karaoke loses vocals.
  static TwoStemOutput separateForVocalRemover({
    required Float32List left,
    required Float32List right,
  }) {
    final length = math.min(left.length, right.length);
    final mono = Float32List(length);
    final mid = Float32List(length);
    final side = Float32List(length);

    for (var i = 0; i < length; i++) {
      mid[i] = (left[i] + right[i]) * 0.5;
      side[i] = (left[i] - right[i]) * 0.5;
      mono[i] = mid[i];
    }

    final harmonicGain = _hpssHarmonicGains(mono, radius: 14);
    final percussiveGain = Float32List(length);
    for (var i = 0; i < length; i++) {
      percussiveGain[i] = (1.0 - harmonicGain[i]).clamp(0.0, 1.0);
    }

    final vocals = Float32List(length);
    final accompaniment = Float32List(length);

    const sideBleed = ProcessingConstants.dspSideBleedReject;
    const cancel = ProcessingConstants.dspVocalCancelStrength;
    const sideBlend = ProcessingConstants.dspSideInstrumentalBlend;
    const gateThreshold = ProcessingConstants.dspNonVocalGateThreshold;

    for (var i = 0; i < length; i++) {
      final midAbs = mid[i].abs();
      final sideAbs = side[i].abs();
      final centerRatio = midAbs / (midAbs + sideAbs + 1e-9);

      // Vocals are harmonic and centered; drums/bass are often percussive or wide.
      final vocalMask = (0.15 + 0.50 * harmonicGain[i] + 0.35 * centerRatio)
          .clamp(0.0, 1.0);

      var vocalEst = mid[i] * harmonicGain[i];
      vocalEst -= sideBleed * side[i];
      vocalEst -= percussiveGain[i] * mid[i] * 0.55;
      vocalEst *= vocalMask;

      if (harmonicGain[i] < gateThreshold) {
        final gate = harmonicGain[i] / gateThreshold;
        vocalEst *= gate * gate;
      }

      vocals[i] = vocalEst;

      final instL = left[i] - cancel * vocalEst;
      final instR = right[i] - cancel * vocalEst;
      var instMono = (instL + instR) * 0.5;
      instMono += side[i] * sideBlend * percussiveGain[i];
      instMono -= harmonicGain[i] * vocalEst * 0.35;

      accompaniment[i] = instMono;
    }

    _highPassInPlace(
      vocals,
      cutoffHz: ProcessingConstants.dspVocalHighPassHz,
      sampleRate: ProcessingConstants.defaultSampleRate,
    );

    _refineStemCrossBleed(
      vocals: vocals,
      accompaniment: accompaniment,
      left: left,
      right: right,
      harmonicGain: harmonicGain,
      percussiveGain: percussiveGain,
    );

    _normalizeInPlace(vocals);
    _normalizeInPlace(accompaniment);
    return TwoStemOutput(vocals: vocals, accompaniment: accompaniment);
  }

  /// Removes instrumental bleed from acapella and vocal residue from karaoke.
  static void _refineStemCrossBleed({
    required Float32List vocals,
    required Float32List accompaniment,
    required Float32List left,
    required Float32List right,
    required Float32List harmonicGain,
    required Float32List percussiveGain,
  }) {
    final length = vocals.length;
    for (var i = 0; i < length; i++) {
      final sideAbs = ((left[i] - right[i]) * 0.5).abs();
      final midAbs = ((left[i] + right[i]) * 0.5).abs();
      final width = sideAbs / (midAbs + 1e-9);

      // Wide stereo = panned instruments — strip from acapella.
      if (width > 0.42 && percussiveGain[i] > 0.45) {
        vocals[i] *= 0.25;
      }

      // Remove instrumental energy correlated with wide/percussive content from vocals.
      vocals[i] -= accompaniment[i] * 0.14 * percussiveGain[i];

      // Karaoke: subtract residual vocal harmonics again.
      accompaniment[i] -= vocals[i] * (0.88 + 0.10 * harmonicGain[i]);

      // Where vocals are strong, push harder cancellation on instrumental.
      if (vocals[i].abs() > 0.02 && harmonicGain[i] > 0.5) {
        accompaniment[i] -= vocals[i] * 0.15;
      }

      vocals[i] = vocals[i].clamp(-1.0, 1.0);
      accompaniment[i] = accompaniment[i].clamp(-1.0, 1.0);
    }
  }

  /// One-pole high-pass — removes sub-bass / kick bleed from acapella.
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

  /// Per-sample harmonic (slow) vs percussive (fast) energy ratio in [0, 1].
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

  /// Original placeholder: left channel only.
  static Method2Stems _legacyLeft(Float32List left, Float32List right) {
    final length = math.min(left.length, right.length);
    final vocals = Float32List(length);
    final drums = Float32List(length);
    for (var i = 0; i < length; i++) {
      vocals[i] = left[i];
      final accompaniment = left[i] * 0.35 + right[i] * 0.65;
      drums[i] = accompaniment * 0.6;
    }
    return Method2Stems(vocals: _normalize(vocals), drums: _normalize(drums));
  }

  /// Mid = (L+R)/2 (center-panned vocals); side = |L-R|/2 as drums proxy.
  static Method2Stems _midSide(Float32List left, Float32List right) {
    final length = math.min(left.length, right.length);
    final vocals = Float32List(length);
    final drums = Float32List(length);
    for (var i = 0; i < length; i++) {
      final mid = (left[i] + right[i]) * 0.5;
      final side = (left[i] - right[i]) * 0.5;
      vocals[i] = mid;
      drums[i] = side.abs();
    }
    return Method2Stems(vocals: _normalize(vocals), drums: _normalize(drums));
  }

  /// Reinforced center vocals: mid minus a fraction of side bleed.
  static Method2Stems _centerCancel(Float32List left, Float32List right) {
    final length = math.min(left.length, right.length);
    final vocals = Float32List(length);
    final drums = Float32List(length);
    const bleed = 0.22;
    for (var i = 0; i < length; i++) {
      final mid = (left[i] + right[i]) * 0.5;
      final side = (left[i] - right[i]) * 0.5;
      vocals[i] = mid - bleed * side;
      drums[i] = side.abs() * 1.15 + mid.abs() * 0.08;
    }
    return Method2Stems(vocals: _normalize(vocals), drums: _normalize(drums));
  }

  /// HPSS-lite: slow (harmonic/vocal) vs fast (percussive) frame energy split.
  static Method2Stems _hpssLite(Float32List left, Float32List right) {
    final length = math.min(left.length, right.length);
    final mono = Float32List(length);
    for (var i = 0; i < length; i++) {
      mono[i] = (left[i] + right[i]) * 0.5;
    }

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

    final harmonic = _movingAverage(frameEnergy, radius: 12);
    final vocals = Float32List(length);
    final drums = Float32List(length);

    for (var i = 0; i < length; i++) {
      final frameIndex =
          (i / hopLength).floor().clamp(0, frameCount - 1);
      final total = frameEnergy[frameIndex];
      final slow = harmonic[frameIndex];
      final fast = math.max(0.0, total - slow);
      final vocalGain = total > 1e-9 ? slow / total : 0.5;
      final drumGain = total > 1e-9 ? fast / total : 0.5;
      vocals[i] = mono[i] * vocalGain;
      drums[i] = mono[i] * drumGain;
    }

    return Method2Stems(vocals: _normalize(vocals), drums: _normalize(drums));
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

  static Float32List _normalize(Float32List samples) {
    _normalizeInPlace(samples);
    return samples;
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
