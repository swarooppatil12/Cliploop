import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/segment.dart';

/// Combines vocal + drums stems and stitches out interludes with crossfade.
class GaplessMixService {
  GaplessMixService._();

  static const double defaultVocalWeight = 0.55;
  static const double defaultDrumsWeight = 0.45;
  static const int defaultCrossfadeMs = 80;

  static Float32List combineStems({
    required Float32List vocals,
    Float32List? drums,
    double vocalWeight = defaultVocalWeight,
    double drumsWeight = defaultDrumsWeight,
  }) {
    final length = math.max(vocals.length, drums?.length ?? 0);
    final mixed = Float32List(length);
    for (var i = 0; i < length; i++) {
      final v = i < vocals.length ? vocals[i] : 0.0;
      final d = drums != null && i < drums.length ? drums[i] : 0.0;
      mixed[i] = v * vocalWeight + d * drumsWeight;
    }
    return _normalizePeak(mixed);
  }

  static List<(double start, double end)> keepRegions({
    required double duration,
    required List<Segment> structureSegments,
  }) {
    final interludes = structureSegments
        .where((s) => s.type == SegmentType.interlude)
        .toList()
      ..sort((a, b) => a.startSeconds.compareTo(b.startSeconds));

    final regions = <(double, double)>[];
    var cursor = 0.0;

    for (final il in interludes) {
      final start = il.startSeconds.clamp(0.0, duration);
      final end = il.endSeconds.clamp(0.0, duration);
      if (start > cursor + 0.02) {
        regions.add((cursor, start));
      }
      cursor = math.max(cursor, end);
    }

    if (cursor < duration - 0.02) {
      regions.add((cursor, duration));
    }

    return regions;
  }

  static GaplessMixResult buildGaplessMix({
    required Float32List vocals,
    Float32List? drums,
    required int sampleRate,
    required double duration,
    required List<Segment> structureSegments,
    int crossfadeMs = defaultCrossfadeMs,
    double vocalWeight = defaultVocalWeight,
    double drumsWeight = defaultDrumsWeight,
  }) {
    final combined = combineStems(
      vocals: vocals,
      drums: drums,
      vocalWeight: vocalWeight,
      drumsWeight: drumsWeight,
    );
    final interludeCount = structureSegments
        .where((s) => s.type == SegmentType.interlude)
        .length;
    final regions = keepRegions(
      duration: duration,
      structureSegments: structureSegments,
    );

    if (interludeCount == 0) {
      return GaplessMixResult(
        samples: combined,
        originalDurationSeconds: duration,
        newDurationSeconds: duration,
        removedSeconds: 0,
        interludeCount: 0,
        regionCount: regions.length,
      );
    }

    final crossfadeSamples = math.max(
      0,
      (crossfadeMs / 1000 * sampleRate).round(),
    );
    final gapless = _stitchRegions(
      combined,
      sampleRate,
      regions,
      crossfadeSamples,
    );

    final newDuration = gapless.length / sampleRate;
    return GaplessMixResult(
      samples: gapless,
      originalDurationSeconds: duration,
      newDurationSeconds: newDuration,
      removedSeconds: duration - newDuration,
      interludeCount: interludeCount,
      regionCount: regions.length,
      crossfadeMs: crossfadeMs,
    );
  }

  static Future<String> writeWav({
    required String outputPath,
    required Float32List samples,
    required int sampleRate,
  }) async {
    final file = File(outputPath);
    await file.parent.create(recursive: true);

    final dataSize = samples.length * 2;
    final builder = BytesBuilder();
    builder.add(_ascii('RIFF'));
    builder.add(_int32Le(36 + dataSize));
    builder.add(_ascii('WAVE'));
    builder.add(_ascii('fmt '));
    builder.add(_int32Le(16));
    builder.add(_int16Le(1));
    builder.add(_int16Le(1));
    builder.add(_int32Le(sampleRate));
    builder.add(_int32Le(sampleRate * 2));
    builder.add(_int16Le(2));
    builder.add(_int16Le(16));
    builder.add(_ascii('data'));
    builder.add(_int32Le(dataSize));

    for (final sample in samples) {
      final clamped = sample.clamp(-1.0, 1.0);
      builder.add(_int16Le((clamped * 32767).round()));
    }

    await file.writeAsBytes(builder.toBytes(), flush: true);
    return outputPath;
  }

  static Float32List _stitchRegions(
    Float32List mix,
    int sampleRate,
    List<(double start, double end)> regions,
    int crossfadeSamples,
  ) {
    if (regions.isEmpty) {
      return Float32List(0);
    }

    final pieces = <Float32List>[];
    for (final (start, end) in regions) {
      final s = (start * sampleRate).floor();
      final e = (end * sampleRate).floor().clamp(s, mix.length);
      pieces.add(mix.sublist(s, e));
    }

    if (pieces.length == 1) {
      return Float32List.fromList(pieces.first);
    }

    var totalLen = pieces.first.length;
    for (var i = 1; i < pieces.length; i++) {
      totalLen += math.max(0, pieces[i].length - crossfadeSamples);
    }

    final out = Float32List(math.max(1, totalLen));
    out.setRange(0, pieces.first.length, pieces.first);
    var writePos = pieces.first.length;

    for (var i = 1; i < pieces.length; i++) {
      final cur = pieces[i];
      final fade = math.min(crossfadeSamples, math.min(writePos, cur.length));

      if (fade > 1) {
        for (var j = 0; j < fade; j++) {
          final t = j / fade;
          out[writePos - fade + j] =
              out[writePos - fade + j] * (1 - t) + cur[j] * t;
        }
        final rest = cur.sublist(fade);
        out.setRange(writePos - fade + fade, writePos - fade + fade + rest.length, rest);
        writePos = writePos - fade + cur.length;
      } else {
        out.setRange(writePos, writePos + cur.length, cur);
        writePos += cur.length;
      }
    }

    return Float32List.sublistView(out, 0, writePos);
  }

  static Float32List _normalizePeak(Float32List samples, [double target = 0.98]) {
    var peak = 0.0;
    for (final s in samples) {
      peak = math.max(peak, s.abs());
    }
    if (peak < 1e-6) {
      return samples;
    }
    final scale = target / peak;
    final out = Float32List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      out[i] = samples[i] * scale;
    }
    return out;
  }

  static List<int> _ascii(String value) => value.codeUnits;

  static List<int> _int16Le(int value) => [value & 0xff, (value >> 8) & 0xff];

  static List<int> _int32Le(int value) => [
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ];
}

class GaplessMixResult {
  const GaplessMixResult({
    required this.samples,
    required this.originalDurationSeconds,
    required this.newDurationSeconds,
    required this.removedSeconds,
    required this.interludeCount,
    required this.regionCount,
    this.crossfadeMs = GaplessMixService.defaultCrossfadeMs,
  });

  final Float32List samples;
  final double originalDurationSeconds;
  final double newDurationSeconds;
  final double removedSeconds;
  final int interludeCount;
  final int regionCount;
  final int crossfadeMs;
}
