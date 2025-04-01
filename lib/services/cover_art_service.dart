import 'dart:io';
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class CoverArtService {
  static const String _imageCacheDirName = 'image_cache';

  Future<Directory> _getImageCacheDirectory() async {
    final appSupportDir = await getApplicationSupportDirectory();
    final imageDir = Directory(p.join(appSupportDir.path, _imageCacheDirName));
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    return imageDir;
  }

  Future<String> getImageCacheDirectoryPath() async {
    final dir = await _getImageCacheDirectory();
    return dir.path;
  }

  String _generateFilename(int igdbId, String coverUrl) {
    final extension = p.extension(coverUrl).split('?').first;
    return '$igdbId${extension.isNotEmpty ? extension : '.jpg'}';
  }

  Future<String?> downloadAndSaveCover(int igdbId, String coverUrl) async {
    if (coverUrl.isEmpty) return null;
    try {
      final imageDir = await _getImageCacheDirectory();
      final filename = _generateFilename(igdbId, coverUrl);
      final filePath = p.join(imageDir.path, filename);
      final file = File(filePath);

      debugPrint('Attempting to download cover from: $coverUrl');
      final response = await http.get(Uri.parse(coverUrl));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('Saved cover for $igdbId to $filePath');
        return filePath;
      } else {
        debugPrint('Failed to download cover for $igdbId: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error downloading/saving cover for $igdbId: $e');
      return null;
    }
  }

  Future<String?> getLocalCoverPath(int igdbId, String? coverUrl) async {
    if (coverUrl == null || coverUrl.isEmpty) return null;
    try {
      final imageDir = await _getImageCacheDirectory();
      final filename = _generateFilename(igdbId, coverUrl);
      final filePath = p.join(imageDir.path, filename);
      final file = File(filePath);

      if (await file.exists()) {
        return filePath;
      } else {
        // Attempt download only if file doesn't exist
        return await downloadAndSaveCover(igdbId, coverUrl);
      }
    } catch (e) {
      debugPrint('Error getting local cover path for $igdbId: $e');
      return null;
    }
  }

  // --- Screenshot Handling ---

  String _generateScreenshotFilename(String screenshotUrl) {
    final urlHash = screenshotUrl.hashCode.toRadixString(16);
    final extension = p.extension(screenshotUrl).split('?').first;
    return 'ss_${urlHash}${extension.isNotEmpty ? extension : '.jpg'}';
  }

  Future<String?> _downloadAndSaveScreenshot(String screenshotUrl) async {
    if (screenshotUrl.isEmpty) return null;
    try {
      final imageDir = await _getImageCacheDirectory();
      final filename = _generateScreenshotFilename(screenshotUrl);
      final filePath = p.join(imageDir.path, filename);
      final file = File(filePath);

      debugPrint('Attempting to download screenshot from: $screenshotUrl');
      final response = await http.get(Uri.parse(screenshotUrl));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('Saved screenshot to $filePath');
        return filePath;
      } else {
        debugPrint('Failed to download screenshot $screenshotUrl: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error downloading/saving screenshot $screenshotUrl: $e');
      return null;
    }
  }

  Future<String?> getLocalScreenshotPath(String? screenshotUrl) async {
    if (screenshotUrl == null || screenshotUrl.isEmpty) return null;
    try {
      final imageDir = await _getImageCacheDirectory();
      final filename = _generateScreenshotFilename(screenshotUrl);
      final filePath = p.join(imageDir.path, filename);
      final file = File(filePath);

      if (await file.exists()) {
        return filePath;
      } else {
        // Attempt download only if file doesn't exist
        return await _downloadAndSaveScreenshot(screenshotUrl);
      }
    } catch (e) {
      debugPrint('Error getting local screenshot path for $screenshotUrl: $e');
      return null;
    }
  }

  Future<List<String>> getLocalScreenshotPaths(List<String> screenshotUrls) async {
    final List<String> localPaths = [];
    for (final url in screenshotUrls) {
      final localPath = await getLocalScreenshotPath(url);
      if (localPath != null) {
        localPaths.add(localPath);
      }
    }
    return localPaths;
  }

  // --- End Screenshot Handling ---

  Future<void> deleteCover(String? localCoverPath) async {
    if (localCoverPath == null || localCoverPath.isEmpty) return;
    try {
      final file = File(localCoverPath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('Deleted cover: $localCoverPath');
      }
    } catch (e) {
      debugPrint('Error deleting cover $localCoverPath: $e');
    }
  }
}