import 'dart:io';

class FileHelper {
  FileHelper._();

  static String fileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  static String fileExtension(String path) {
    final name = fileName(path);
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) {
      return '';
    }
    return name.substring(dotIndex + 1).toLowerCase();
  }

  static Future<int> fileSizeBytes(String path) async {
    return File(path).length();
  }

  static Future<bool> fileExists(String path) async {
    return File(path).exists();
  }

  static Future<String> uniqueFileName(String fileName) async {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1) {
      return '${fileName}_${DateTime.now().millisecondsSinceEpoch}';
    }
    final base = fileName.substring(0, dotIndex);
    final ext = fileName.substring(dotIndex);
    return '${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
  }

  static String joinPath(String part1, String part2, [String? part3, String? part4]) {
    final parts = [part1, part2, ?part3, ?part4];
    return parts.join(Platform.pathSeparator);
  }

  static String fileExtensionWithDot(String path) {
    final name = fileName(path);
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1) {
      return '';
    }
    return name.substring(dotIndex);
  }

  static String baseNameWithoutExtension(String path) {
    final name = fileName(path);
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1) {
      return name;
    }
    return name.substring(0, dotIndex);
  }
}
