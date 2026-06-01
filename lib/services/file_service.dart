import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/file_helper.dart';
import '../models/music_file.dart';

class FileService {
  FileService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  String? _tracksRootPath;

  Future<MusicFile?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConstants.supportedAudioExtensions,
      allowMultiple: false,
      withReadStream: false,
      withData: false,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final pickedFile = result.files.first;
    final path = pickedFile.path;
    if (path == null || path.isEmpty) {
      return null;
    }

    return importToAppLibrary(
      sourcePath: path,
      displayName: pickedFile.name,
    );
  }

  /// Copies [sourcePath] into the app library and returns a [MusicFile] record.
  Future<MusicFile> importToAppLibrary({
    required String sourcePath,
    String? displayName,
    String? existingId,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw Exception('Audio file not found: $sourcePath');
    }

    final tracksDir = await _tracksDirectory();
    final id = existingId ?? _uuid.v4();
    final name = displayName ?? FileHelper.fileName(sourcePath);
    final extension = FileHelper.fileExtensionWithDot(sourcePath);
    final safeBase = _sanitizeFileName(FileHelper.baseNameWithoutExtension(name));
    final destinationPath = FileHelper.joinPath(
      tracksDir.path,
      '${safeBase}_$id$extension',
    );

    final String storedPath;
    if (_isUnderAppTracks(sourcePath)) {
      storedPath = sourcePath;
    } else {
      await source.copy(destinationPath);
      storedPath = destinationPath;
    }

    final storedFile = File(storedPath);
    final stat = await storedFile.stat();
    final durationSeconds = await _readDurationSeconds(storedFile.path);

    return MusicFile(
      id: id,
      name: name,
      path: storedFile.path,
      durationSeconds: durationSeconds,
      fileSizeBytes: stat.size,
      receivedAt: DateTime.now(),
    );
  }

  Future<void> deleteFromAppLibrary(MusicFile file) async {
    final trackFile = File(file.path);
    if (await trackFile.exists()) {
      await trackFile.delete();
    }

    final stemsRoot = await _stemsRootDirectory();
    if (await stemsRoot.exists()) {
      await for (final entity in stemsRoot.list()) {
        if (entity is! Directory) {
          continue;
        }
        var shouldDelete = false;
        await for (final item in entity.list(recursive: true)) {
          if (item.path.contains(file.id)) {
            shouldDelete = true;
            break;
          }
        }
        if (shouldDelete) {
          await entity.delete(recursive: true);
        }
      }
    }
  }

  Future<List<MusicFile>> getRecentFiles() async {
    final cacheFile = await _cacheFile();
    if (!await cacheFile.exists()) {
      return [];
    }

    final raw = await cacheFile.readAsString();
    if (raw.trim().isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return [];
    }

    final files = <MusicFile>[];
    for (final item in decoded.whereType<Map>()) {
      final file = MusicFile.fromJson(Map<String, dynamic>.from(item));
      if (await File(file.path).exists()) {
        files.add(file);
      }
    }

    files.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return files;
  }

  Future<void> cacheFile(MusicFile file) async {
    final files = await getRecentFiles();
    files.removeWhere((existing) => existing.id == file.id || existing.path == file.path);
    files.insert(0, file);
    await saveRecentFiles(files);
  }

  Future<void> saveRecentFiles(List<MusicFile> files) async {
    final cacheFile = await _cacheFile();
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(
      jsonEncode(files.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> saveSelectedFileId(String? fileId) async {
    final cacheFile = await _selectedFileCacheFile();
    await cacheFile.parent.create(recursive: true);

    if (fileId == null || fileId.isEmpty) {
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
      return;
    }

    await cacheFile.writeAsString(
      jsonEncode({'selected_file_id': fileId}),
      flush: true,
    );
  }

  Future<String?> getSelectedFileId() async {
    final cacheFile = await _selectedFileCacheFile();
    if (!await cacheFile.exists()) {
      return null;
    }

    final raw = await cacheFile.readAsString();
    if (raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }

    return decoded['selected_file_id'] as String?;
  }

  Future<void> saveToDownloads(String path, String fileName) async {
    final source = File(path);
    if (!await source.exists()) {
      throw Exception('Source file not found: $path');
    }

    if (Platform.isAndroid) {
      final storageStatus = await Permission.storage.request();
      if (!storageStatus.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }

    final downloadsDirectory = await _resolveDownloadsDirectory();
    await downloadsDirectory.create(recursive: true);

    final safeName = await FileHelper.uniqueFileName(fileName);
    final destinationPath = FileHelper.joinPath(downloadsDirectory.path, safeName);
    await source.copy(destinationPath);
  }

  Future<Directory> tracksDirectory() => _tracksDirectory();

  /// Waits until `path_provider`'s JNI bridge is attached before any real
  /// directory access. On Android, `path_provider_android` calls into
  /// `package:jni`, which is not ready during the warm-up frame — touching it
  /// then throws "No JNI instance is available" and corrupts the JNI env,
  /// hard-crashing the process (SIGSEGV in libdartjni.so / FindClass).
  /// Yielding off the frame and retrying lets the engine finish attaching.
  Future<void> ensureStorageReady() async {
    Object? lastError;
    for (var attempt = 0; attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      try {
        await getApplicationDocumentsDirectory();
        return;
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('path_provider not ready after retries: $lastError');
  }

  bool isStoredInApp(String path) => _isUnderAppTracks(path);

  Future<File> _selectedFileCacheFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(
      FileHelper.joinPath(directory.path, AppConstants.selectedFileCacheFile),
    );
  }

  Future<File> _cacheFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(FileHelper.joinPath(directory.path, AppConstants.recentFilesCacheFile));
  }

  Future<Directory> _tracksDirectory() async {
    if (_tracksRootPath != null) {
      return Directory(_tracksRootPath!);
    }
    final directory = await getApplicationDocumentsDirectory();
    final tracksDir = Directory(
      FileHelper.joinPath(directory.path, AppConstants.tracksCacheDir),
    );
    await tracksDir.create(recursive: true);
    _tracksRootPath = tracksDir.path;
    return tracksDir;
  }

  Future<Directory> _stemsRootDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final stemsDir = Directory(
      FileHelper.joinPath(directory.path, AppConstants.stemsCacheDir),
    );
    await stemsDir.create(recursive: true);
    return stemsDir;
  }

  Future<Directory> _resolveDownloadsDirectory() async {
    if (Platform.isAndroid) {
      final downloads = Directory(
        FileHelper.joinPath('/storage/emulated/0/Download', AppConstants.downloadsSubDir),
      );
      if (await downloads.parent.exists()) {
        return downloads;
      }
    }

    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return Directory(
        FileHelper.joinPath(downloads.path, AppConstants.downloadsSubDir),
      );
    }

    final documents = await getApplicationDocumentsDirectory();
    return Directory(
      FileHelper.joinPath(documents.path, AppConstants.downloadsSubDir),
    );
  }

  bool _isUnderAppTracks(String path) {
    final root = _tracksRootPath;
    if (root == null) {
      return path.contains(
        '${Platform.pathSeparator}${AppConstants.tracksCacheDir}${Platform.pathSeparator}',
      );
    }
    return path.startsWith(root);
  }

  String _sanitizeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^\w\-. ]+'), '_').trim();
    return cleaned.isEmpty ? 'track' : cleaned;
  }

  Future<int> _readDurationSeconds(String path) async {
    final player = AudioPlayer();
    try {
      final duration = await player.setFilePath(path).then((_) => player.duration);
      return duration?.inSeconds ?? 0;
    } catch (_) {
      return 0;
    } finally {
      await player.dispose();
    }
  }
}
