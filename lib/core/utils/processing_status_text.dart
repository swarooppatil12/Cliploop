import '../constants/processing_constants.dart';
import '../../providers/music_provider.dart';

String processingStepText({
  required ActiveProcessingMethod method,
  required ProcessingState state,
  required int progress,
}) {
  if (state == ProcessingState.preparing) {
    if (progress <= 1) {
      return 'Starting…';
    }
    if (progress <= 3) {
      return 'Keeping device awake for processing…';
    }
    return 'Preparing audio…';
  }

  if (state == ProcessingState.processing) {
    if (method == ActiveProcessingMethod.spleeter) {
      if (progress < 25) {
        return 'Downloading mobile ML model (one time)…';
      }
      if (progress < 55) {
        return 'Separating vocals & instrumental…';
      }
      return progress >= 80
          ? 'Finding Prelude, Interlude & Postlude…'
          : 'Running Silero voice detection…';
    }

    if (progress < 18) {
      return 'Decoding your song…';
    }
    if (progress < 28) {
      return 'Downloading UVR model (one time)…';
    }
    if (progress < 68) {
      return 'Separating vocals & instrumental (ML)…';
    }
    if (progress < 90) {
      return 'Running ${ProcessingConstants.svadModelLabel} voice detection…';
    }
    return 'Detecting song structure…';
  }

  if (state == ProcessingState.complete) {
    return 'Complete';
  }

  if (state == ProcessingState.error) {
    return 'Failed';
  }

  return 'Preparing…';
}
