import 'dart:math' as math;

/// Time-region helpers shared by structure and ML vocal detection.
class RegionUtils {
  RegionUtils._();

  static List<(double, double)> merge(
    List<(double, double)> regions, {
    double gap = 0.35,
  }) {
    if (regions.isEmpty) {
      return [];
    }

    final sorted = List<(double, double)>.from(regions)
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(double, double)>[sorted.first];

    for (var index = 1; index < sorted.length; index++) {
      final (start, end) = sorted[index];
      final last = merged.last;
      if (start - last.$2 <= gap) {
        merged[merged.length - 1] = (last.$1, math.max(last.$2, end));
      } else {
        merged.add((start, end));
      }
    }

    return merged;
  }
}
