import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

enum CoverSize {
  small,
  medium,
  large,
}

class Settings {
  final String prefixDirectory;
  final String igdbClientId;
  final String igdbClientSecret;
  final String? igdbAccessToken;
  final DateTime? igdbTokenExpiry;
  final CoverSize coverSize;
  final List<String> categories;
  final String? gameLibraryPath; // Path to save the prefix/game data JSON

  Settings({
    required this.prefixDirectory,
    required this.igdbClientId,
    required this.igdbClientSecret,
    this.igdbAccessToken,
    this.igdbTokenExpiry,
    this.coverSize = CoverSize.medium,
    required this.categories,
    this.gameLibraryPath, // Add to constructor
  });

  Map<String, dynamic> toJson() => {
    'prefixDirectory': prefixDirectory,
    'igdbClientId': igdbClientId,
    'igdbClientSecret': igdbClientSecret,
    'igdbAccessToken': igdbAccessToken,
    'igdbTokenExpiry': igdbTokenExpiry?.toIso8601String(),
    'coverSize': coverSize.toString(),
    'categories': categories,
    'gameLibraryPath': gameLibraryPath, // Add to toJson
  };

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
    prefixDirectory: json['prefixDirectory'] ?? '',
    igdbClientId: json['igdbClientId'] ?? '',
    igdbClientSecret: json['igdbClientSecret'] ?? '',
    igdbAccessToken: json['igdbAccessToken'],
    igdbTokenExpiry: json['igdbTokenExpiry'] != null
      ? DateTime.parse(json['igdbTokenExpiry'])
      : null,
    coverSize: json['coverSize'] != null
      ? CoverSize.values.firstWhere(
          (e) => e.toString() == json['coverSize'],
          orElse: () => CoverSize.medium,
        )
      : CoverSize.medium,
    categories: (json['categories'] as List<dynamic>?)?.cast<String>() ??
               ['Favorites', 'Currently Playing', 'Completed', 'Backlog'],
    gameLibraryPath: json['gameLibraryPath'], // Add to fromJson
  );
}

class AppSettings {
  static Future<Settings> load() async {
    try {
      final homeDir = Platform.environment['HOME']!;
      final file = File('$homeDir/.wine_prefix_manager_settings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        return Settings.fromJson(jsonDecode(content));
      }
    } catch (e) {
      print('Error loading settings: $e');
    }

    // Return default settings
    final homeDir = Platform.environment['HOME']!;
    return Settings(
      prefixDirectory: path.join(homeDir, '.wine_prefixes'), // Use path.join
      igdbClientId: '',
      igdbClientSecret: '',
      categories: ['Favorites', 'Currently Playing', 'Completed', 'Backlog'],
      gameLibraryPath: null, // Default is null
    );
  }

  static Future<void> save(Settings settings) async {
    try {
      final homeDir = Platform.environment['HOME']!;
      final file = File('$homeDir/.wine_prefix_manager_settings.json');
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (e) {
      print('Error saving settings: $e');
    }
  }

  static Future<Settings> updateToken(Settings settings, String token, Duration expiry) async {
    final updatedSettings = Settings(
      prefixDirectory: settings.prefixDirectory,
      igdbClientId: settings.igdbClientId,
      igdbClientSecret: settings.igdbClientSecret,
      igdbAccessToken: token,
      igdbTokenExpiry: DateTime.now().add(expiry),
      coverSize: settings.coverSize,
      categories: settings.categories,
      gameLibraryPath: settings.gameLibraryPath, // Pass through gameLibraryPath
    );

    await save(updatedSettings);
    return updatedSettings;
  }
}
