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
  final String? gameLibraryPath;
  final String? backupPath; // Add backupPath field

  // API and Service URLs
  final String dxvkApiUrl;
  final String vkd3dApiUrl;
  final String wineBuildsApiUrl;
  final String protonGeApiUrl;
  final String protonExperimentalApiUrl;
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
    this.gameLibraryPath,
    this.backupPath, // Add to constructor
    this.dxvkApiUrl = 'https://api.github.com/repos/doitsujin/dxvk/releases/latest',
    this.vkd3dApiUrl = 'https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest',
    this.wineBuildsApiUrl = 'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.4',
    this.protonGeApiUrl = 'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases',
    this.protonExperimentalApiUrl = 'https://api.github.com/repos/ValveSoftware/Proton/releases',
    this.twitchOAuthUrl = 'https://id.twitch.tv/oauth2/token',
    this.igdbApiBaseUrl = 'https://api.igdb.com/v4',
    required this.igdbImageBaseUrl,
  });

  Map<String, dynamic> toJson() => {
        'prefixDirectory': prefixDirectory,
        'igdbClientId': igdbClientId,
        'igdbClientSecret': igdbClientSecret,
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
        'protonExperimentalApiUrl': protonExperimentalApiUrl,
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
        gameLibraryPath: json['gameLibraryPath'],
        backupPath: json['backupPath'], // Add to fromJson
        dxvkApiUrl: json['dxvkApiUrl'] ??
            'https://api.github.com/repos/doitsujin/dxvk/releases/latest',
        vkd3dApiUrl: json['vkd3dApiUrl'] ??
            'https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest',
        wineBuildsApiUrl: json['wineBuildsApiUrl'] ??
            'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.4',
        protonGeApiUrl: json['protonGeApiUrl'] ??
            'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases',
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
    String? igdbClientId,
    String? igdbClientSecret,
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
    String? protonExperimentalApiUrl,
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
      backupPath: backupPath ?? this.backupPath, // Add logic
      dxvkApiUrl: dxvkApiUrl ?? this.dxvkApiUrl,
      vkd3dApiUrl: vkd3dApiUrl ?? this.vkd3dApiUrl,
      wineBuildsApiUrl: wineBuildsApiUrl ?? this.wineBuildsApiUrl,
      protonGeApiUrl: protonGeApiUrl ?? this.protonGeApiUrl,
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
  static Future<Settings> load() async {
    try {
      final homeDir = Platform.environment['HOME']!;
      final file = File('$homeDir/.wine_prefix_manager_settings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        return Settings.fromJson(jsonDecode(content));
      }
    } catch (e) {}

    final homeDir = Platform.environment['HOME']!;
    return Settings(
      prefixDirectory: path.join(homeDir, '.wine_prefixes'),
      igdbClientId: '',
      igdbClientSecret: '',
      categories: ['Favorites', 'Currently Playing', 'Completed', 'Backlog'],
      gameLibraryPath: null,
      backupPath: null,
      dxvkApiUrl: 'https://api.github.com/repos/doitsujin/dxvk/releases/latest',
      vkd3dApiUrl:
          'https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest',
      wineBuildsApiUrl:
          'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.4',
      protonGeApiUrl:
          'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases',
      protonExperimentalApiUrl:
          'https://api.github.com/repos/ValveSoftware/Proton/releases',
      twitchOAuthUrl: 'https://id.twitch.tv/oauth2/token',
      igdbApiBaseUrl: 'https://api.igdb.com/v4',
      igdbImageBaseUrl: 'https://images.igdb.com/igdb/image/upload',
    );
  }

  static Future<void> save(Settings settings) async {
    try {
      final homeDir = Platform.environment['HOME']!;
      final file = File('$homeDir/.wine_prefix_manager_settings.json');
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (e) {}
  }

  static Future<Settings> updateToken(
      Settings settings, String token, Duration expiry) async {
    final updatedSettings = Settings(
      prefixDirectory: settings.prefixDirectory,
      igdbClientId: settings.igdbClientId,
      igdbClientSecret: settings.igdbClientSecret,
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
      protonExperimentalApiUrl: settings.protonExperimentalApiUrl,
      twitchOAuthUrl: settings.twitchOAuthUrl,
      igdbApiBaseUrl: settings.igdbApiBaseUrl,
      igdbImageBaseUrl: settings.igdbImageBaseUrl,
    );

    await save(updatedSettings);
    return updatedSettings;
  }
}
