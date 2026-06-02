import Flutter
import UIKit

/// iOS plugin registrar. Separation/inference on iOS runs through Core ML via
/// `flutter_onnxruntime` (Dart side) — there is no native QNN channel here, so
/// this registers as a no-op and `QnnMdxRuntime` falls back to the ONNX path.
public class CliploopHighlightsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    _ = registrar
  }
}
