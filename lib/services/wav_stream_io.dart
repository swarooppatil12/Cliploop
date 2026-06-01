import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/constants/processing_constants.dart';

/// Parsed PCM WAV metadata for streaming reads.
class WavStreamInfo {
  const WavStreamInfo({
    required this.sampleRate,
    required this.channels,
    required this.frameCount,
    required this.dataOffset,
    required this.file,
  });

  final int sampleRate;
  final int channels;
  final int frameCount;
  final int dataOffset;
  final File file;

  double get durationSeconds =>
      sampleRate == 0 ? 0 : frameCount / sampleRate;
}

/// Incrementally writes mono 16-bit PCM WAV (header patched on [finalize]).
class MonoWavWriter {
  MonoWavWriter._(this._raf, this.sampleRate);

  static const int _headerBytes = 44;

  final RandomAccessFile _raf;
  final int sampleRate;
  int _framesWritten = 0;

  static Future<MonoWavWriter> create(String path, int sampleRate) async {
    final raf = await File(path).open(mode: FileMode.write);
    await raf.writeFrom(Uint8List(_headerBytes));
    return MonoWavWriter._(raf, sampleRate);
  }

  int get framesWritten => _framesWritten;

  Future<void> writeFloat32Mono(
    Float32List samples, {
    int offset = 0,
    int? length,
  }) async {
    final count = length ?? (samples.length - offset);
    if (count <= 0) {
      return;
    }

    await _raf.setPosition(_headerBytes + _framesWritten * 2);
    const batch = 4096;
    var written = 0;
    while (written < count) {
      final n = math.min(batch, count - written);
      final bytes = ByteData(n * 2);
      for (var i = 0; i < n; i++) {
        final sample = samples[offset + written + i].clamp(-1.0, 1.0);
        bytes.setInt16(i * 2, (sample * 32767).round(), Endian.little);
      }
      await _raf.writeFrom(
        bytes.buffer.asUint8List(bytes.offsetInBytes, n * 2),
      );
      written += n;
    }
    _framesWritten += count;
  }

  Future<void> finalize() async {
    final dataSize = _framesWritten * 2;
    final header = ByteData(_headerBytes);
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, 36 + dataSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6d); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    await _raf.setPosition(0);
    await _raf.writeFrom(header.buffer.asUint8List());
    await _raf.close();
  }
}

Future<WavStreamInfo> openWavStream(File file) async {
  final raf = await file.open();
  try {
    final fileLength = await raf.length();
    if (fileLength < 44) {
      throw Exception('Invalid WAV file: ${file.path}');
    }

    var offset = 12;
    var sampleRate = ProcessingConstants.defaultSampleRate;
    var channels = 2;
    var bitsPerSample = 16;
    var dataOffset = -1;
    var dataSize = 0;

    while (offset + 8 <= fileLength) {
      await raf.setPosition(offset);
      final chunkHeader = await raf.read(8);
      if (chunkHeader.length < 8) {
        break;
      }

      final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
      final chunkSize =
          ByteData.sublistView(chunkHeader).getUint32(4, Endian.little);
      final chunkDataOffset = offset + 8;

      if (chunkId == 'fmt ') {
        final fmt = await raf.read(math.min(chunkSize, 16));
        if (fmt.length >= 16) {
          final fmtData = ByteData.sublistView(fmt);
          channels = fmtData.getUint16(2, Endian.little);
          sampleRate = fmtData.getUint32(4, Endian.little);
          bitsPerSample = fmtData.getUint16(14, Endian.little);
        }
      } else if (chunkId == 'data') {
        dataOffset = chunkDataOffset;
        dataSize = chunkSize;
        break;
      }

      offset = chunkDataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (dataOffset < 0) {
      throw Exception('WAV data chunk not found: ${file.path}');
    }
    if (bitsPerSample != 16) {
      throw Exception('Only 16-bit WAV is supported: ${file.path}');
    }
    if (dataSize <= 0) {
      dataSize = fileLength - dataOffset;
    }

    final frameCount = dataSize ~/ (channels * 2);
    return WavStreamInfo(
      sampleRate: sampleRate,
      channels: channels,
      frameCount: frameCount,
      dataOffset: dataOffset,
      file: file,
    );
  } finally {
    await raf.close();
  }
}

/// Reads a stereo window from disk without loading the full file.
Future<({Float32List left, Float32List right})> readWavStereoWindow(
  WavStreamInfo info,
  int startFrame,
  int frameCount,
) async {
  final start = startFrame.clamp(0, info.frameCount);
  final count = math.min(frameCount, info.frameCount - start);
  final left = Float32List(count);
  final right = Float32List(count);
  if (count == 0) {
    return (left: left, right: right);
  }

  final raf = await info.file.open();
  try {
    final channels = info.channels;
    const batchFrames = 8192;
    var frame = 0;
    while (frame < count) {
      final batch = math.min(batchFrames, count - frame);
      final byteOffset =
          info.dataOffset + (start + frame) * channels * 2;
      await raf.setPosition(byteOffset);
      final byteCount = batch * channels * 2;
      final chunk = await raf.read(byteCount);
      if (chunk.isEmpty) {
        break;
      }

      final chunkData = ByteData.sublistView(chunk);
      final framesInChunk = chunk.length ~/ (channels * 2);
      for (var i = 0; i < framesInChunk; i++) {
        final index = i * channels * 2;
        final l = chunkData.getInt16(index, Endian.little) / 32768.0;
        final r = channels > 1
            ? chunkData.getInt16(index + 2, Endian.little) / 32768.0
            : l;
        left[frame + i] = l;
        right[frame + i] = r;
      }
      frame += framesInChunk;
    }
  } finally {
    await raf.close();
  }

  return (left: left, right: right);
}

/// Loads full stereo channels from a PCM WAV file.
Future<({Float32List left, Float32List right})> loadStereoFromWav(
  String path,
) async {
  final info = await openWavStream(File(path));
  if (info.channels < 2) {
    throw Exception('Expected stereo WAV at $path');
  }

  final left = Float32List(info.frameCount);
  final right = Float32List(info.frameCount);
  final raf = await info.file.open();

  try {
    final channels = info.channels;
    const batchFrames = 8192;
    var frame = 0;

    while (frame < info.frameCount) {
      final batch = math.min(batchFrames, info.frameCount - frame);
      await raf.setPosition(info.dataOffset + frame * channels * 2);
      final chunk = await raf.read(batch * channels * 2);
      if (chunk.isEmpty) {
        break;
      }

      final chunkData = ByteData.sublistView(chunk);
      final framesInChunk = chunk.length ~/ (channels * 2);
      for (var i = 0; i < framesInChunk; i++) {
        final index = i * channels * 2;
        left[frame + i] = chunkData.getInt16(index, Endian.little) / 32768.0;
        right[frame + i] =
            chunkData.getInt16(index + 2, Endian.little) / 32768.0;
      }
      frame += framesInChunk;
    }
  } finally {
    await raf.close();
  }

  return (left: left, right: right);
}

/// Scales all samples in a mono 16-bit WAV by [gain] without loading the full file.
Future<void> scaleMonoWavInPlace(String path, double gain) async {
  if (gain == 1.0 || gain.isNaN || gain.isInfinite || gain <= 0) {
    return;
  }

  final info = await openWavStream(File(path));
  final tempPath = '$path.scaled';
  final writer = await MonoWavWriter.create(tempPath, info.sampleRate);
  final raf = await File(path).open(mode: FileMode.read);

  try {
    const batchFrames = 8192;
    var frame = 0;
    while (frame < info.frameCount) {
      final batch = math.min(batchFrames, info.frameCount - frame);
      await raf.setPosition(info.dataOffset + frame * 2);
      final bytes = await raf.read(batch * 2);
      if (bytes.isEmpty) {
        break;
      }

      final data = ByteData.sublistView(bytes);
      final framesInChunk = bytes.length ~/ 2;
      final scaled = Float32List(framesInChunk);
      for (var i = 0; i < framesInChunk; i++) {
        final sample = data.getInt16(i * 2, Endian.little) / 32768.0;
        scaled[i] = (sample * gain).clamp(-1.0, 1.0);
      }

      await writer.writeFloat32Mono(scaled);
      frame += framesInChunk;
    }
  } finally {
    await raf.close();
  }

  await writer.finalize();
  await File(path).delete();
  await File(tempPath).rename(path);
}

/// Loads mono samples from a mono or stereo WAV (uses average if stereo).
Future<Float32List> loadMonoFromWav(String path) async {
  final info = await openWavStream(File(path));
  final raf = await info.file.open();
  try {
    final mono = Float32List(info.frameCount);
    final channels = info.channels;
    const batchFrames = 8192;
    var frame = 0;

    while (frame < info.frameCount) {
      final batch = math.min(batchFrames, info.frameCount - frame);
      await raf.setPosition(info.dataOffset + frame * channels * 2);
      final chunk = await raf.read(batch * channels * 2);
      if (chunk.isEmpty) {
        break;
      }

      final chunkData = ByteData.sublistView(chunk);
      final framesInChunk = chunk.length ~/ (channels * 2);
      for (var i = 0; i < framesInChunk; i++) {
        final index = i * channels * 2;
        final l = chunkData.getInt16(index, Endian.little) / 32768.0;
        if (channels > 1) {
          final r = chunkData.getInt16(index + 2, Endian.little) / 32768.0;
          mono[frame + i] = (l + r) * 0.5;
        } else {
          mono[frame + i] = l;
        }
      }
      frame += framesInChunk;
    }

    return mono;
  } finally {
    await raf.close();
  }
}

/// Instrumental reference for structure rules: full mix minus isolated vocals.
///
/// Keeps vocal/instrumental energy ratios aligned with the original song when
/// ML stems are peak-normalized separately (e.g. Core ML UVR).
Future<Float32List> computeMixMinusVocalMono({
  required String wavPath,
  required Float32List vocalMono,
}) async {
  final mix = await loadMonoFromWav(wavPath);
  final n = math.min(mix.length, vocalMono.length);
  if (n <= 0) {
    return Float32List(0);
  }

  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = (mix[i] - vocalMono[i]).clamp(-1.0, 1.0);
  }
  return out;
}
