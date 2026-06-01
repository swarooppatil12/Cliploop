import 'package:sherpa_onnx/sherpa_onnx.dart';

/// Lazily loads sherpa-onnx native bindings on first use instead of at app launch.
void ensureSherpaBindings() {
  initBindings();
}
