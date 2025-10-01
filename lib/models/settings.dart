import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../utils/path_utils.dart';
import '../utils/logger.dart';

enum CoverSize {
  small,
  medium,
  large,
}

class Settings {
  final String prefixDirectory;
  final String? igdbAccessToken;
  final DateTime? igdbTokenExpiry;
  final CoverSize coverSize;
  final List<String> categories;
  final String? gameLibraryPath;
  final String? backupPath; // Add backupPath field

  // API and Service URLs
  final String dxvkApiUrl;
  final String vkd3dApiUrl;
  final String wineBuildsApiUrl;
  final String protonGeApiUrl;
  final String kronekProtonApiUrl; // Add URL for Kron4ek Proton builds
  final String cachyOSProtonApiUrl; // Add URL for CachyOS Proton builds
  final String protonExperimentalApiUrl;
  final String twitchOAuthUrl;
  final String igdbApiBaseUrl;
  final String igdbImageBaseUrl;

  Settings({
    required this.prefixDirectory,
    this.igdbAccessToken,
    this.igdbTokenExpiry,
    this.coverSize = CoverSize.medium,
    required this.categories,
    this.gameLibraryPath,
    this.backupPath, // Add to constructor
    this.dxvkApiUrl = 'https://api.github.com/repos/doitsujin/dxvk/releases/latest',
    this.vkd3dApiUrl = 'https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest',
    this.wineBuildsApiUrl = 'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.15',
    this.protonGeApiUrl = 'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases',
    this.kronekProtonApiUrl = 'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.15',
    this.cachyOSProtonApiUrl = 'https://api.github.com/repos/CachyOS/proton-cachyos/releases',
    this.protonExperimentalApiUrl = 'https://api.github.com/repos/ValveSoftware/Proton/releases',
    this.twitchOAuthUrl = 'https://id.twitch.tv/oauth2/token',
    this.igdbApiBaseUrl = 'https://api.igdb.com/v4',
    required this.igdbImageBaseUrl,
  });

  Map<String, dynamic> toJson() => {
        'prefixDirectory': prefixDirectory,
        'igdbAccessToken': igdbAccessToken,
        'igdbTokenExpiry': igdbTokenExpiry?.toIso8601String(),
        'coverSize': coverSize.toString(),
        'categories': categories,
        'gameLibraryPath': gameLibraryPath,
        'backupPath': backupPath, // Add to toJson
        'dxvkApiUrl': dxvkApiUrl,
        'vkd3dApiUrl': vkd3dApiUrl,
        'wineBuildsApiUrl': wineBuildsApiUrl,
        'protonGeApiUrl': protonGeApiUrl,
        'kronekProtonApiUrl': kronekProtonApiUrl,
        'cachyOSProtonApiUrl': cachyOSProtonApiUrl,
        'protonExperimentalApiUrl': protonExperimentalApiUrl,
        'twitchOAuthUrl': twitchOAuthUrl,
        'igdbApiBaseUrl': igdbApiBaseUrl,
        'igdbImageBaseUrl': igdbImageBaseUrl,
      };

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
        prefixDirectory: json['prefixDirectory'] ?? '',
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
        gameLibraryPath: json['gameLibraryPath'],
        backupPath: json['backupPath'], // Add to fromJson
        dxvkApiUrl: json['dxvkApiUrl'] ??
            'https://api.github.com/repos/doitsujin/dxvk/releases/latest',
        vkd3dApiUrl: json['vkd3dApiUrl'] ??
            'https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest',
    wineBuildsApiUrl: json['wineBuildsApiUrl'] ??
      'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.15',
        protonGeApiUrl: json['protonGeApiUrl'] ??
            'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases',
    kronekProtonApiUrl: json['kronekProtonApiUrl'] ??
      'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.15',
    cachyOSProtonApiUrl: json['cachyOSProtonApiUrl'] ??
      'https://api.github.com/repos/CachyOS/proton-cachyos/releases',
    protonExperimentalApiUrl: json['protonExperimentalApiUrl'] ??
      'https://api.github.com/repos/ValveSoftware/Proton/releases',
        twitchOAuthUrl: json['twitchOAuthUrl'] ??
            'https://id.twitch.tv/oauth2/token',
        igdbApiBaseUrl: json['igdbApiBaseUrl'] ?? 'https://api.igdb.com/v4',
        igdbImageBaseUrl: (json['igdbImageBaseUrl'] != null &&
                json['igdbImageBaseUrl'].isNotEmpty)
            ? json['igdbImageBaseUrl']
            : 'https://images.igdb.com/igdb/image/upload',
      );

  Settings copyWith({
    String? prefixDirectory,
    String? igdbAccessToken,
    DateTime? igdbTokenExpiry,
    CoverSize? coverSize,
    List<String>? categories,
    String? gameLibraryPath,
    String? backupPath, // Add to copyWith
    String? dxvkApiUrl,
    String? vkd3dApiUrl,
    String? wineBuildsApiUrl,
    String? protonGeApiUrl,
    String? kronekProtonApiUrl,
    String? cachyOSProtonApiUrl,
    String? protonExperimentalApiUrl,
    String? twitchOAuthUrl,
    String? igdbApiBaseUrl,
    String? igdbImageBaseUrl,
  }) {
    return Settings(
      prefixDirectory: prefixDirectory ?? this.prefixDirectory,
      igdbAccessToken: igdbAccessToken ?? this.igdbAccessToken,
      igdbTokenExpiry: igdbTokenExpiry ?? this.igdbTokenExpiry,
      coverSize: coverSize ?? this.coverSize,
      categories: categories ?? this.categories,
      gameLibraryPath: gameLibraryPath ?? this.gameLibraryPath,
      backupPath: backupPath ?? this.backupPath, // Add logic
      dxvkApiUrl: dxvkApiUrl ?? this.dxvkApiUrl,
      vkd3dApiUrl: vkd3dApiUrl ?? this.vkd3dApiUrl,
      wineBuildsApiUrl: wineBuildsApiUrl ?? this.wineBuildsApiUrl,
      protonGeApiUrl: protonGeApiUrl ?? this.protonGeApiUrl,
      kronekProtonApiUrl: kronekProtonApiUrl ?? this.kronekProtonApiUrl,
      cachyOSProtonApiUrl: cachyOSProtonApiUrl ?? this.cachyOSProtonApiUrl,
      protonExperimentalApiUrl:
          protonExperimentalApiUrl ?? this.protonExperimentalApiUrl,
      twitchOAuthUrl: twitchOAuthUrl ?? this.twitchOAuthUrl,
      igdbApiBaseUrl: igdbApiBaseUrl ?? this.igdbApiBaseUrl,
      igdbImageBaseUrl: igdbImageBaseUrl ?? this.igdbImageBaseUrl,
    );
  }

  String get buildsApiUrl => 'https://api.default-builds-url.com';
}

class AppSettings {
  static const String _settingsFileName = 'settings.json';
  static const String _defaultPrefixesSubDir = 'prefixes';
  static const String _defaultGameLibraryFileName = 'game_library.json';

  static Future<Settings> load() async {
    final baseAppDataPath = await getBaseAppDataPath();
    final settingsFilePath = path.join(baseAppDataPath, _settingsFileName);

    try {
      final file = File(settingsFilePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return Settings.fromJson(jsonDecode(content));
        }
      }
    } catch (e) {
      logError('Error loading settings from $settingsFilePath', e);
    }

    // Fallback to default settings
    return Settings(
      prefixDirectory: path.join(baseAppDataPath, _defaultPrefixesSubDir),
      gameLibraryPath: path.join(baseAppDataPath, _defaultGameLibraryFileName),
      igdbAccessToken: null,
      igdbTokenExpiry: null,
      coverSize: CoverSize.medium,
      categories: ['Favorites', 'Currently Playing', 'Completed', 'Backlog'],
      backupPath: null,
      dxvkApiUrl: 'https://api.github.com/repos/doitsujin/dxvk/releases/latest',
      vkd3dApiUrl:
          'https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest',
    wineBuildsApiUrl:
      'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.15',
    protonGeApiUrl:
      'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases',
    kronekProtonApiUrl:
      'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.15',
    cachyOSProtonApiUrl:
      'https://api.github.com/repos/CachyOS/proton-cachyos/releases',
    protonExperimentalApiUrl:
      'https://api.github.com/repos/ValveSoftware/Proton/releases',
      twitchOAuthUrl: 'https://id.twitch.tv/oauth2/token',
      igdbApiBaseUrl: 'https://api.igdb.com/v4',
      igdbImageBaseUrl: 'https://images.igdb.com/igdb/image/upload',
    );
  }

  static Future<void> save(Settings settings) async {
    final baseAppDataPath = await getBaseAppDataPath();
    final settingsFilePath = path.join(baseAppDataPath, _settingsFileName);

    try {
      final dir = Directory(baseAppDataPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        logInfo('Created base app data directory: $baseAppDataPath');
      }

      final file = File(settingsFilePath);
      Settings settingsToSave = settings;

      if (settings.gameLibraryPath == null || settings.gameLibraryPath!.isEmpty) {
        // Ensure default gameLibraryPath is set if null/empty when saving
         settingsToSave = settings.copyWith(gameLibraryPath: path.join(baseAppDataPath, _defaultGameLibraryFileName));
      }
      if (settings.prefixDirectory.isEmpty) {
        // Ensure default prefixDirectory is set if empty when saving
        settingsToSave = settingsToSave.copyWith(prefixDirectory: path.join(baseAppDataPath, _defaultPrefixesSubDir));
      }
      
      // If the current settings object has a null gameLibraryPath (even after above default),
      // try to preserve an existing one from the file on disk. This is more of a safety net.
      if (settingsToSave.gameLibraryPath == path.join(baseAppDataPath, _defaultGameLibraryFileName) && await file.exists()) {
         // This logic was to preserve an old path, with new defaults this might need rethinking
         // For now, if it's the default path, we assume it's okay or it's a fresh save.
      }


      // Preserve existing gameLibraryPath if current one is null (original logic)
      // This might conflict with setting a new default above, so reviewing.
      // The goal: if settings.gameLibraryPath is truly unset by user, use new default.
      // If it *was* set, but somehow became null in memory, try to keep the old one.
      // The copyWith above should handle setting new defaults if they were empty/null.
      
      // Simplified: The copyWith should ensure paths are non-null using new defaults if they were originally null/empty.
      // The preservation logic for gameLibraryPath from disk if current is null might be redundant
      // if we are already defaulting it. Let's ensure the defaults are robustly applied.

      if (settings.gameLibraryPath == null && await file.exists()) {
        try {
          final existingContent = await file.readAsString();
          if (existingContent.isNotEmpty) {
            final existingJson = jsonDecode(existingContent);
            final existingGameLibraryPath = existingJson['gameLibraryPath'] as String?;
            if (existingGameLibraryPath != null && existingGameLibraryPath.isNotEmpty) {
              // If an old valid path exists and current settings has it null, preserve it.
              // This might be for settings loaded before path consolidation.
              logInfo('Preserving existing gameLibraryPath from file: $existingGameLibraryPath over current null value.');
              settingsToSave = settingsToSave.copyWith(gameLibraryPath: existingGameLibraryPath);
            }
          }
        } catch (e) {
          logError('Error trying to preserve gameLibraryPath from disk', e);
        }
      }


      await file.writeAsString(jsonEncode(settingsToSave.toJson()));
    } catch (e) {
      logError('Error saving settings to $settingsFilePath', e);
    }
  }

  static Future<Settings> updateToken(
      Settings settings, String token, Duration expiry) async {
    final updatedSettings = Settings(
      prefixDirectory: settings.prefixDirectory,
      igdbAccessToken: token,
      igdbTokenExpiry: DateTime.now().add(expiry),
      coverSize: settings.coverSize,
      categories: settings.categories,
      gameLibraryPath: settings.gameLibraryPath,
      backupPath: settings.backupPath,
      dxvkApiUrl: settings.dxvkApiUrl,
      vkd3dApiUrl: settings.vkd3dApiUrl,
      wineBuildsApiUrl: settings.wineBuildsApiUrl,
      protonGeApiUrl: settings.protonGeApiUrl,
      kronekProtonApiUrl: settings.kronekProtonApiUrl,
      protonExperimentalApiUrl: settings.protonExperimentalApiUrl,
      twitchOAuthUrl: settings.twitchOAuthUrl,
      igdbApiBaseUrl: settings.igdbApiBaseUrl,
      igdbImageBaseUrl: settings.igdbImageBaseUrl,
    );

    await save(updatedSettings);
    return updatedSettings;
  }

  static Future<Settings> updateIgdbToken(Settings settings, String token, Duration expiry) async {
    final updatedSettings = Settings(
      prefixDirectory: settings.prefixDirectory,
      igdbAccessToken: token,
      igdbTokenExpiry: DateTime.now().add(expiry),
      coverSize: settings.coverSize,
      categories: settings.categories,
      gameLibraryPath: settings.gameLibraryPath,
      backupPath: settings.backupPath,
      dxvkApiUrl: settings.dxvkApiUrl,
      vkd3dApiUrl: settings.vkd3dApiUrl,
      wineBuildsApiUrl: settings.wineBuildsApiUrl,
      protonGeApiUrl: settings.protonGeApiUrl,
      kronekProtonApiUrl: settings.kronekProtonApiUrl,
      protonExperimentalApiUrl: settings.protonExperimentalApiUrl,
      twitchOAuthUrl: settings.twitchOAuthUrl,
      igdbApiBaseUrl: settings.igdbApiBaseUrl,
      igdbImageBaseUrl: settings.igdbImageBaseUrl,
    );

    await save(updatedSettings);
    return updatedSettings;
  }
}
