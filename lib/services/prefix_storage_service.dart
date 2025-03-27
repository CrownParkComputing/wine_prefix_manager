import 'dart:convert';
import 'dart:io';
import '../models/prefix_models.dart'; // Adjust import path as needed

class PrefixStorageService {
  final String _configFileName = '.wine_prefix_manager.json';

  Future<String> _getConfigPath() async {
    final homeDir = Platform.environment['HOME'];
    if (homeDir == null) {
      throw Exception('HOME environment variable not set.');
    }
    return '$homeDir/$_configFileName';
  }

  Future<List<WinePrefix>> loadPrefixes() async {
    try {
      final filePath = await _getConfigPath();
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isEmpty) {
          // Handle empty file case
          return [];
        }
        final List<dynamic> jsonList = jsonDecode(content);
        return jsonList.map((p) => WinePrefix.fromJson(p)).toList();
      }
    } catch (e) {
      print('Error loading prefixes: $e');
      // Depending on requirements, might rethrow, return empty list, or handle differently
    }
    return []; // Return empty list if file doesn't exist or on error
  }

  Future<void> savePrefixes(List<WinePrefix> prefixes) async {
    try {
      final filePath = await _getConfigPath();
      final file = File(filePath);
      final jsonString = jsonEncode(prefixes.map((p) => p.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      print('Error saving prefixes: $e');
      // Rethrow or handle as appropriate
      rethrow;
    }
  }
}