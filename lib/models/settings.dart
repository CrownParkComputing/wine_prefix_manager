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

  // API and Service URLs
  final String dxvkApiUrl;
  final String vkd3dApiUrl;
  final String wineBuildsApiUrl;
  final String protonGeApiUrl;
  final String twitchOAuthUrl;
  final String igdbApiBaseUrl;
  final String igdbImageBaseUrl;

  Settings({
    required this.prefixDirectory,
    required this.igdbClientId,
    required this.igdbClientSecret,
    this.igdbAccessToken,
    this.igdbTokenExpiry,
    this.coverSize = CoverSize.medium,
    required this.categories,
    this.gameLibraryPath, // Add to constructor
    // Add new URL fields (optional with defaults)
    this.dxvkApiUrl = 'https://api.github.com/repos/doitsujin/dxvk/releases/latest',
    this.vkd3dApiUrl = 'https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest',
    this.wineBuildsApiUrl = 'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.4', // Consider making tag configurable later
    this.protonGeApiUrl = 'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases',
    this.twitchOAuthUrl = 'https://id.twitch.tv/oauth2/token',
    this.igdbApiBaseUrl = 'https://api.igdb.com/v4',
    required this.igdbImageBaseUrl, // Make it required, handle default in fromJson/load
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
    // Add URLs to toJson
    'dxvkApiUrl': dxvkApiUrl,
    'vkd3dApiUrl': vkd3dApiUrl,
    'wineBuildsApiUrl': wineBuildsApiUrl,
    'protonGeApiUrl': protonGeApiUrl,
    'twitchOAuthUrl': twitchOAuthUrl,
    'igdbApiBaseUrl': igdbApiBaseUrl,
    'igdbImageBaseUrl': igdbImageBaseUrl,
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
   // Add URLs to fromJson, providing defaults if missing
   dxvkApiUrl: json['dxvkApiUrl'] ?? 'https://api.github.com/repos/doitsujin/dxvk/releases/latest',
   vkd3dApiUrl: json['vkd3dApiUrl'] ?? 'https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest',
   wineBuildsApiUrl: json['wineBuildsApiUrl'] ?? 'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.4',
   protonGeApiUrl: json['protonGeApiUrl'] ?? 'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases',
   twitchOAuthUrl: json['twitchOAuthUrl'] ?? 'https://id.twitch.tv/oauth2/token',
   igdbApiBaseUrl: json['igdbApiBaseUrl'] ?? 'https://api.igdb.com/v4',
   // Robust default handling for igdbImageBaseUrl
   igdbImageBaseUrl: (json['igdbImageBaseUrl'] != null && json['igdbImageBaseUrl'].isNotEmpty)
                      ? json['igdbImageBaseUrl']
                      : 'https://images.igdb.com/igdb/image/upload', // Default if null or empty
 );

  Settings copyWith({
    String? prefixDirectory,
    String? igdbClientId,
    String? igdbClientSecret,
    String? igdbAccessToken,
    DateTime? igdbTokenExpiry,
    CoverSize? coverSize,
    List<String>? categories,
    String? gameLibraryPath,
    String? dxvkApiUrl,
    String? vkd3dApiUrl,
    String? wineBuildsApiUrl,
    String? protonGeApiUrl,
    String? twitchOAuthUrl,
    String? igdbApiBaseUrl,
    String? igdbImageBaseUrl,
  }) {
    return Settings(
      prefixDirectory: prefixDirectory ?? this.prefixDirectory,
      igdbClientId: igdbClientId ?? this.igdbClientId,
      igdbClientSecret: igdbClientSecret ?? this.igdbClientSecret,
      igdbAccessToken: igdbAccessToken ?? this.igdbAccessToken,
      igdbTokenExpiry: igdbTokenExpiry ?? this.igdbTokenExpiry,
      coverSize: coverSize ?? this.coverSize,
      categories: categories ?? this.categories,
      gameLibraryPath: gameLibraryPath ?? this.gameLibraryPath,
      dxvkApiUrl: dxvkApiUrl ?? this.dxvkApiUrl,
      vkd3dApiUrl: vkd3dApiUrl ?? this.vkd3dApiUrl,
      wineBuildsApiUrl: wineBuildsApiUrl ?? this.wineBuildsApiUrl,
      protonGeApiUrl: protonGeApiUrl ?? this.protonGeApiUrl,
      twitchOAuthUrl: twitchOAuthUrl ?? this.twitchOAuthUrl,
      igdbApiBaseUrl: igdbApiBaseUrl ?? this.igdbApiBaseUrl,
      // Ensure non-nullable field is handled correctly
      igdbImageBaseUrl: igdbImageBaseUrl ?? this.igdbImageBaseUrl,
    );
  }

  // Add the missing buildsApiUrl property
  String get buildsApiUrl => 'https://api.default-builds-url.com';  // Add default URL
  
  // Add a setter if you need to allow changing this value
  // set buildsApiUrl(String url) {
  //   // Implement using your existing storage mechanism
  // }

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
      gameLibraryPath: null,
      // Provide ALL required fields for the default constructor call
      dxvkApiUrl: 'https://api.github.com/repos/doitsujin/dxvk/releases/latest',
      vkd3dApiUrl: 'https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest',
      wineBuildsApiUrl: 'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.4',
      protonGeApiUrl: 'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases',
      twitchOAuthUrl: 'https://id.twitch.tv/oauth2/token',
      igdbApiBaseUrl: 'https://api.igdb.com/v4',
      igdbImageBaseUrl: 'https://images.igdb.com/igdb/image/upload', // Correct default
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
      // Pass through URL fields
      dxvkApiUrl: settings.dxvkApiUrl,
      vkd3dApiUrl: settings.vkd3dApiUrl,
      wineBuildsApiUrl: settings.wineBuildsApiUrl,
      protonGeApiUrl: settings.protonGeApiUrl,
      twitchOAuthUrl: settings.twitchOAuthUrl,
      igdbApiBaseUrl: settings.igdbApiBaseUrl,
      igdbImageBaseUrl: settings.igdbImageBaseUrl,
    );

    await save(updatedSettings);
    return updatedSettings;
  }
}
