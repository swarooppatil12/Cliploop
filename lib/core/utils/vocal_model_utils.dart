import '../constants/processing_constants.dart';

class VocalModelUtils {
  VocalModelUtils._();

  static String label(String modelId) {
    return ProcessingConstants.method2VocalModels[modelId] ?? modelId;
  }

  static List<String> get modelIds =>
      ProcessingConstants.method2VocalModels.keys.toList();
}
