import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path; // Import path package
import '../models/prefix_models.dart';
import '../models/settings.dart'; // Import Settings model
import '../utils/path_utils.dart'; // Import the new utility

class PrefixStorageService {
  static const String _appName = 'wine_prefix_manager'; // Match AppSettings
  static const String _defaultGameLibraryFileName = 'game_library.json'; // Match AppSettings

  /// Determines the path for the prefix data file.
  /// Uses the path from settings if provided, otherwise defaults to the app data directory.
  Future<String> _getConfigPath(Settings settings) async {
    // Use custom path if provided and not empty
    if (settings.gameLibraryPath != null && settings.gameLibraryPath!.isNotEmpty) {
      try {
        final dir = Directory(path.dirname(settings.gameLibraryPath!));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return settings.gameLibraryPath!;
      } catch (e) {
        print('Warning: Could not create directory for custom game library path: ${settings.gameLibraryPath}. Error: $e');
        // Fallback to default path if directory creation for custom path fails
        return _getDefaultConfigPath();
      }
    }
    // Fallback to default path
    return _getDefaultConfigPath();
  }

  /// Gets the default configuration path in the application's data directory.
  Future<String> _getDefaultConfigPath() async {
    final baseAppDataPath = await getBaseAppDataPath(); // Use imported function
    final gameLibPath = path.join(baseAppDataPath, _defaultGameLibraryFileName);
    // Ensure the directory exists when getting the default path too
    try {
      final dir = Directory(path.dirname(gameLibPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
       print('Warning: Could not create directory for default game library path: $gameLibPath. Error: $e');
       // If it fails, it will likely fail on write later, but we try to be proactive.
    }
    return gameLibPath;
  }

  /// Loads prefixes from the configured path.
  Future<List<WinePrefix>> loadPrefixes(Settings settings) async { // Accept Settings
    try {
      final filePath = await _getConfigPath(settings); // Pass settings
      // Loading prefixes from: $filePath
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isEmpty) {
          // Handle empty file case
          return [];
        }
        final List<dynamic> jsonList = jsonDecode(content);
        return jsonList.map((p) => WinePrefix.fromJson(p)).toList();
      } else {
        // Prefix file not found at: $filePath
      }
    } catch (e) {
      // Error loading prefixes
      // Depending on requirements, might rethrow, return empty list, or handle differently
    }
    return []; // Return empty list if file doesn't exist or on error
  }

  /// Saves prefixes to the configured path.
  Future<void> savePrefixes(List<WinePrefix> prefixes, Settings settings) async { // Accept Settings
    try {
      final filePath = await _getConfigPath(settings); // Pass settings
      // Saving prefixes to: $filePath
      final file = File(filePath);
      // Ensure the directory exists before writing
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        // Created directory for saving prefixes
      }
      final jsonString = jsonEncode(prefixes.map((p) => p.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      // Error saving prefixes
      // Rethrow or handle as appropriate
      rethrow;
    }
  }
}