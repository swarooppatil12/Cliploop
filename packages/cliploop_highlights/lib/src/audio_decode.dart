import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'processing_constants.dart';

const _uuid = Uuid();

/// A decoded WAV ready for separation. [isTemporary] files are deleted by the caller.
class DecodedWav {
  const DecodedWav(this.path, {required this.isTemporary});
  final String path;
  final bool isTemporary;
}

/// Decode any audio file to 16-bit stereo PCM WAV at the model sample rate.
///
/// Always routed through ffmpeg (even for .wav) so a 24-bit / float source can't
/// slip through — the separation reader only accepts 16-bit PCM.
Future<DecodedWav> decodeToWav16(String inputPath) async {
  final tempDir = await getTemporaryDirectory();
  final wavPath = '${tempDir.path}/cliploop_${_uuid.v4()}.wav';
  final cmd =
      '-y -i "$inputPath" -ac 2 -ar ${ProcessingConstants.defaultSampleRate} '
      '-c:a pcm_s16le "$wavPath"';
  final session = await FFmpegKit.execute(cmd);
  if (!ReturnCode.isSuccess(await session.getReturnCode())) {
    final logs = await session.getAllLogsAsString();
    throw Exception('cliploop_highlights: audio decode failed — ${logs ?? "ffmpeg error"}');
  }
  return DecodedWav(wavPath, isTemporary: true);
}
