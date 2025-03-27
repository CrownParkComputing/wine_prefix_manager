import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path; // Import path package
import '../models/prefix_models.dart';
import '../models/settings.dart'; // Import Settings model

class PrefixStorageService {
  final String _defaultConfigFileName = '.wine_prefix_manager.json';

  /// Determines the path for the prefix data file.
  /// Uses the path from settings if provided, otherwise defaults to the home directory.
  Future<String> _getConfigPath(Settings settings) async {
    // Use custom path if provided and not empty
    if (settings.gameLibraryPath != null && settings.gameLibraryPath!.isNotEmpty) {
      // Ensure the directory exists for the custom path
      try {
        final dir = Directory(path.dirname(settings.gameLibraryPath!));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
          print('Created directory for custom game library path: ${dir.path}');
        }
      } catch (e) {
        print('Warning: Could not create directory for custom game library path: $e');
        // Fallback to default path if directory creation fails
        return _getDefaultConfigPath();
      }
      return settings.gameLibraryPath!;
    }

    // Fallback to default path
    return _getDefaultConfigPath();
  }

  /// Gets the default configuration path in the user's home directory.
  Future<String> _getDefaultConfigPath() async {
    final homeDir = Platform.environment['HOME'];
    if (homeDir == null) {
      throw Exception('HOME environment variable not set.');
    }
    return path.join(homeDir, _defaultConfigFileName); // Use path.join
  }

  /// Loads prefixes from the configured path.
  Future<List<WinePrefix>> loadPrefixes(Settings settings) async { // Accept Settings
    try {
      final filePath = await _getConfigPath(settings); // Pass settings
      print('Loading prefixes from: $filePath'); // Log the path being used
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
        print('Prefix file not found at: $filePath');
      }
    } catch (e) {
      print('Error loading prefixes: $e');
      // Depending on requirements, might rethrow, return empty list, or handle differently
    }
    return []; // Return empty list if file doesn't exist or on error
  }

  /// Saves prefixes to the configured path.
  Future<void> savePrefixes(List<WinePrefix> prefixes, Settings settings) async { // Accept Settings
    try {
      final filePath = await _getConfigPath(settings); // Pass settings
      print('Saving prefixes to: $filePath'); // Log the path being used
      final file = File(filePath);
      // Ensure the directory exists before writing
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        print('Created directory for saving prefixes: ${dir.path}');
      }
      final jsonString = jsonEncode(prefixes.map((p) => p.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      print('Error saving prefixes: $e');
      // Rethrow or handle as appropriate
      rethrow;
    }
  }
}