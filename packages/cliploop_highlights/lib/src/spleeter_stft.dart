import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// STFT / ISTFT matching sherpa-onnx / kaldi-native-fbank (Spleeter pipeline).
class SpleeterStftConfig {
  const SpleeterStftConfig({
    this.nFft = 4096,
    this.hopLength = 1024,
    this.winLength = 4096,
    this.center = false,
  });

  final int nFft;
  final int hopLength;
  final int winLength;
  final bool center;

  int get fftBins => nFft ~/ 2 + 1;
}

class SpleeterStftResult {
  SpleeterStftResult({
    required this.numFrames,
    required this.real,
    required this.imag,
  });

  final int numFrames;
  final Float32List real;
  final Float32List imag;
}

class SpleeterStft {
  SpleeterStft(this.config)
      : _fft = FFT(config.nFft),
        _window = _hannWindow(config.winLength);

  final SpleeterStftConfig config;
  final FFT _fft;
  final Float64List _window;

  static Float64List _hannWindow(int length) {
    final window = Float64List(length);
    if (length <= 0) {
      return window;
    }
    final a = 2 * math.pi / length;
    for (var i = 0; i < length; i++) {
      window[i] = 0.5 - 0.5 * math.cos(a * i);
    }
    return window;
  }

  SpleeterStftResult computeStft(Float32List samples) {
    final nFft = config.nFft;
    final hop = config.hopLength;
    final bins = config.fftBins;
    final padded = _maybeCenterPad(samples);
    final length = padded.length;

    if (length < nFft) {
      return SpleeterStftResult(
        numFrames: 0,
        real: Float32List(0),
        imag: Float32List(0),
      );
    }

    final numFrames = 1 + (length - nFft) ~/ hop;
    final real = Float32List(numFrames * bins);
    final imag = Float32List(numFrames * bins);
    final frame = Float64List(nFft);

    for (var frameIndex = 0; frameIndex < numFrames; frameIndex++) {
      final offset = frameIndex * hop;
      for (var i = 0; i < nFft; i++) {
        frame[i] = padded[offset + i] * _window[i];
      }

      final spectrum = _fft.realFft(frame);
      final base = frameIndex * bins;
      real[base] = spectrum[0].x.toDouble();
      real[base + nFft ~/ 2] = spectrum[nFft ~/ 2].x.toDouble();

      for (var k = 1; k < nFft ~/ 2; k++) {
        real[base + k] = spectrum[k].x.toDouble();
        imag[base + k] = spectrum[k].y.toDouble();
      }
    }

    return SpleeterStftResult(
      numFrames: numFrames,
      real: real,
      imag: imag,
    );
  }

  Float32List computeIstft(SpleeterStftResult stft) {
    final nFft = config.nFft;
    final hop = config.hopLength;
    final bins = config.fftBins;
    final numFrames = stft.numFrames;

    if (numFrames == 0) {
      return Float32List(0);
    }

    final numSamples = nFft + (numFrames - 1) * hop;
    final output = Float64List(numSamples);
    final denominator = _overlapDenominator(numFrames);
    final frame = Float64List(nFft);

    for (var frameIndex = 0; frameIndex < numFrames; frameIndex++) {
      final base = frameIndex * bins;
      final complex = Float64x2List(nFft);
      complex[0] = Float64x2(stft.real[base], 0);
      complex[nFft ~/ 2] = Float64x2(stft.real[base + nFft ~/ 2], 0);

      for (var k = 1; k < nFft ~/ 2; k++) {
        final re = stft.real[base + k];
        final im = stft.imag[base + k];
        complex[k] = Float64x2(re, im);
        complex[nFft - k] = Float64x2(re, -im);
      }

      final timeDomain = _fft.realInverseFft(complex);
      for (var i = 0; i < nFft; i++) {
        frame[i] = timeDomain[i] * _window[i];
      }

      final start = frameIndex * hop;
      for (var i = 0; i < nFft; i++) {
        output[start + i] += frame[i];
      }
    }

    final result = Float32List(numSamples);
    for (var i = 0; i < numSamples; i++) {
      final denom = denominator[i];
      result[i] = denom > 0 ? (output[i] / denom).toDouble() : 0;
    }

    if (config.center) {
      final trim = nFft ~/ 2;
      if (result.length <= config.nFft) {
        return Float32List(0);
      }
      return Float32List.sublistView(result, trim, result.length - trim);
    }

    return result;
  }

  Float32List _maybeCenterPad(Float32List samples) {
    if (!config.center) {
      return samples;
    }
    final pad = config.nFft ~/ 2;
    final padded = Float32List(samples.length + config.nFft);
    padded.setRange(pad, pad + samples.length, samples);
    return padded;
  }

  Float64List _overlapDenominator(int numFrames) {
    final nFft = config.nFft;
    final hop = config.hopLength;
    final numSamples = nFft + (numFrames - 1) * hop;
    final denominator = Float64List(numSamples);

    for (var frameIndex = 0; frameIndex < numFrames; frameIndex++) {
      final start = frameIndex * hop;
      for (var i = 0; i < nFft; i++) {
        final w = _window[i];
        denominator[start + i] += w * w;
      }
    }

    return denominator;
  }
}
