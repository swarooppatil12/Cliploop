import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Runs UVR MDX-Net on the Hexagon NPU (TFLite + QNN delegate) via a Kotlin
/// platform channel. The native interpreter is created once and reused per chunk.
///
/// I/O is the model's flat [1,4,2048,256] float tensor (same layout the ONNX path
/// uses), passed/returned as Float32List (transferred as raw bytes by the codec).
class QnnMdxRuntime {
  QnnMdxRuntime._();
  static final QnnMdxRuntime instance = QnnMdxRuntime._();

  static const MethodChannel _ch = MethodChannel('cliploop_highlights/qnn');

  bool _ready = false;
  bool get ready => _ready;

  /// Creates the NPU interpreter. Returns true only if the QNN/HTP delegate
  /// actually initialized; on any failure returns false (caller falls back).
  Future<bool> init() async {
    if (_ready) return true;
    try {
      final res = await _ch.invokeMethod<Map<dynamic, dynamic>>('init');
      _ready = res != null && res['ok'] == true;
      if (kDebugMode) {
        debugPrint('[QNN] init ${_ready ? "ok" : "FAILED"}: $res');
      }
    } catch (error) {
      if (kDebugMode) debugPrint('[QNN] init threw: $error');
      _ready = false;
    }
    return _ready;
  }

  /// Runs one chunk. [input] is the flat [1,4,2048,256] tensor. Returns the
  /// model output (same shape) or null on failure.
  Future<Float32List?> run(Float32List input) async {
    if (!_ready) return null;
    final out = await _ch.invokeMethod<Float32List>('run', input);
    return out;
  }

  Future<void> close() async {
    try {
      await _ch.invokeMethod<void>('close');
    } catch (_) {}
    _ready = false;
  }
}
