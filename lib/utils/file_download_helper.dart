// lib/utils/file_download_helper.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'dart:io' as io;

class FileDownloadHelper {
  /// Whether the current platform is desktop (Windows, macOS, or Linux)
  static bool get isDesktop =>
      !kIsWeb && (io.Platform.isWindows || io.Platform.isMacOS || io.Platform.isLinux);

  /// Resolves the user's Downloads directory (with Windows USERPROFILE fallback).
  static Future<io.Directory> getSystemDownloadsDirectory() async {
    if (!kIsWeb && io.Platform.isWindows) {
      try {
        final userProfile = io.Platform.environment['USERPROFILE'];
        if (userProfile != null && userProfile.trim().isNotEmpty) {
          final winDownloads = io.Directory('$userProfile\\Downloads');
          if (await winDownloads.exists()) {
            return winDownloads;
          }
        }
      } catch (_) {}
    }

    try {
      final dir = await getDownloadsDirectory();
      if (dir != null && await dir.exists()) {
        return dir;
      }
    } catch (_) {}

    try {
      final docs = await getApplicationDocumentsDirectory();
      return docs;
    } catch (_) {}

    return io.Directory.current;
  }

  /// Opens the folder or selects the file in Windows File Explorer / macOS Finder / Linux file manager.
  static void openInFileManager(String path) {
    if (kIsWeb) return;
    try {
      if (io.Platform.isWindows) {
        final isFile = io.File(path).existsSync();
        if (isFile) {
          io.Process.run('explorer.exe', ['/select,', path]);
        } else {
          io.Process.run('explorer.exe', [path]);
        }
      } else if (io.Platform.isMacOS) {
        io.Process.run('open', ['-R', path]);
      } else if (io.Platform.isLinux) {
        io.Process.run('xdg-open', [path]);
      }
    } catch (e) {
      // Ignore if system file manager call fails
    }
  }

  /// Saves binary data directly to a file in the user's Downloads folder.
  /// Returns the saved absolute file path.
  static Future<String> saveFileToDownloads({
    required String fileName,
    required List<int> bytes,
  }) async {
    final downloadsDir = await getSystemDownloadsDirectory();
    final sanitizedFileName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = '${downloadsDir.path}${io.Platform.pathSeparator}$sanitizedFileName';
    final file = io.File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Saves a ZIP file AND extracts all contained files into a dedicated folder in Downloads.
  /// Returns a map with 'folderPath' and 'zipPath'.
  static Future<Map<String, String>> saveZipAndFolderToDownloads({
    required String zipFileName,
    required String folderName,
    required Archive archive,
    required List<int> zipBytes,
  }) async {
    final downloadsDir = await getSystemDownloadsDirectory();
    final sanitizedFolderName = folderName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final sanitizedZipName = zipFileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    // 1. Save ZIP file
    final zipPath = '${downloadsDir.path}${io.Platform.pathSeparator}$sanitizedZipName';
    await io.File(zipPath).writeAsBytes(zipBytes, flush: true);

    // 2. Create the extracted directory
    final folderPath = '${downloadsDir.path}${io.Platform.pathSeparator}$sanitizedFolderName';
    final folder = io.Directory(folderPath);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    // 3. Write each file from archive into the folder
    for (final file in archive.files) {
      if (file.isFile) {
        final outName = file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final outPath = '$folderPath${io.Platform.pathSeparator}$outName';
        await io.File(outPath).writeAsBytes(file.content as List<int>, flush: true);
      }
    }

    return {
      'folderPath': folderPath,
      'zipPath': zipPath,
    };
  }
}
