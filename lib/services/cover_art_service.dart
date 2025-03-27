import 'dart:io';
import 'dart:typed_data'; // For image bytes
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p; // Use 'p' prefix to avoid conflicts

class CoverArtService {
  static const String _imageCacheDirName = 'image_cache'; // Renamed

  // Method to get the base directory for storing images
  Future<Directory> _getImageCacheDirectory() async { // Renamed method
    final appSupportDir = await getApplicationSupportDirectory();
    // Use the renamed constant _imageCacheDirName here
    final imageDir = Directory(p.join(appSupportDir.path, _imageCacheDirName));
    if (!await imageDir.exists()) { // Use renamed variable
      await imageDir.create(recursive: true); // Use renamed variable
    }
    return imageDir; // Use renamed variable
  }

  // Public method to get the cache directory path string
  Future<String> getImageCacheDirectoryPath() async {
    final dir = await _getImageCacheDirectory();
    return dir.path;
  }
 
  // Method to generate a unique filename (e.g., using igdbId or a hash)
  String _generateFilename(int igdbId, String coverUrl) {
    // Use IGDB ID and maybe a hash of the URL to ensure uniqueness
    // and handle potential URL changes for the same ID.
    // For simplicity now, just use igdbId. Ensure it's filesystem-safe.
    final extension = p.extension(coverUrl).split('?').first; // Get .jpg, .png etc.
    return '$igdbId${extension.isNotEmpty ? extension : '.jpg'}'; // Default to .jpg if no extension
  }

  // Method to download and save the cover
  Future<String?> downloadAndSaveCover(int igdbId, String coverUrl) async {
    if (coverUrl.isEmpty) return null;
    try {
      final imageDir = await _getImageCacheDirectory(); // Use renamed method
      final filename = _generateFilename(igdbId, coverUrl);
      final filePath = p.join(imageDir.path, filename); // Use renamed variable
      final file = File(filePath);

      // Optional: Check if file already exists and is valid?
      // For now, we'll just re-download if called.

      final response = await http.get(Uri.parse(coverUrl));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        print('Saved cover for $igdbId to $filePath');
        return filePath; // Return the local path
      } else {
        print('Failed to download cover for $igdbId: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error downloading/saving cover for $igdbId: $e');
      return null;
    }
  }

  // Method to get the local path if it exists, otherwise trigger download
  Future<String?> getLocalCoverPath(int igdbId, String? coverUrl) async {
    if (coverUrl == null || coverUrl.isEmpty) return null;

    try {
      final imageDir = await _getImageCacheDirectory(); // Use renamed method
      final filename = _generateFilename(igdbId, coverUrl);
      final filePath = p.join(imageDir.path, filename); // Use renamed variable
      final file = File(filePath);

      if (await file.exists()) {
        // Basic check: Does the file exist?
        // Could add more checks (e.g., file size > 0) if needed.
        return filePath;
      } else {
        // File doesn't exist, download it
        return await downloadAndSaveCover(igdbId, coverUrl);
      }
    } catch (e) {
      print('Error getting local cover path for $igdbId: $e');
      return null;
    }
  }

  // --- Screenshot Handling ---

  // Generate filename for screenshot (use hash of URL for uniqueness)
  String _generateScreenshotFilename(String screenshotUrl) {
    // Use a hash of the URL to create a unique filename
    final urlHash = screenshotUrl.hashCode.toRadixString(16);
    final extension = p.extension(screenshotUrl).split('?').first;
    return 'ss_${urlHash}${extension.isNotEmpty ? extension : '.jpg'}';
  }

  // Download and save a single screenshot
  Future<String?> _downloadAndSaveScreenshot(String screenshotUrl) async {
    if (screenshotUrl.isEmpty) return null;

    try {
      final imageDir = await _getImageCacheDirectory();
      final filename = _generateScreenshotFilename(screenshotUrl);
      final filePath = p.join(imageDir.path, filename);
      final file = File(filePath);

      final response = await http.get(Uri.parse(screenshotUrl));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        print('Saved screenshot to $filePath');
        return filePath;
      } else {
        print('Failed to download screenshot $screenshotUrl: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error downloading/saving screenshot $screenshotUrl: $e');
      return null;
    }
  }

  // Get local path for a single screenshot, download if needed
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
        return await _downloadAndSaveScreenshot(screenshotUrl);
      }
    } catch (e) {
      print('Error getting local screenshot path for $screenshotUrl: $e');
      return null;
    }
  }

  // Process a list of screenshot URLs, returning local paths
  Future<List<String>> getLocalScreenshotPaths(List<String> screenshotUrls) async {
    final List<String> localPaths = [];
    for (final url in screenshotUrls) {
      final localPath = await getLocalScreenshotPath(url);
      if (localPath != null) {
        localPaths.add(localPath);
      }
      // Optionally handle cases where download fails - currently just skips
    }
    return localPaths;
  }

  // --- End Screenshot Handling ---


  // Optional: Method to delete a cover if needed (e.g., when prefix/exe is removed)
  // TODO: Consider a generic delete method or specific screenshot delete
  Future<void> deleteCover(String? localCoverPath) async {
    if (localCoverPath == null || localCoverPath.isEmpty) return;
    try {
      final file = File(localCoverPath);
      if (await file.exists()) {
        await file.delete();
        print('Deleted cover: $localCoverPath');
      }
    } catch (e) {
      print('Error deleting cover $localCoverPath: $e');
    }
  }
}