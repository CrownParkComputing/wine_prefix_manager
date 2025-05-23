enum PrefixType {
  wine,
  proton,
}

class WinePrefix {
  final String name;
  final String path;
  final String wineBuildPath;
  final PrefixType type;
  final List<ExeEntry> exeEntries;
  final String architecture; // Added architecture field
  final Map<String, String> environmentVariables; // Environment variables for the prefix

  final List<GameEntry>? gameEntries; // Change to final since the constructor is const

  const WinePrefix({
    required this.name,
    required this.path,
    required this.wineBuildPath,
    required this.type,
    required this.exeEntries,
    required this.architecture, // Added to constructor
    this.gameEntries,
    this.environmentVariables = const {}, // Default to empty map
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'wineBuildPath': wineBuildPath,
    'type': type.toString(), // Stores as "PrefixType.proton", "PrefixType.wine", etc.
    'architecture': architecture, // Added to JSON
    'exeEntries': exeEntries.map((e) => e.toJson()).toList(),
    'environmentVariables': environmentVariables, // Add environment variables to JSON
  };

  factory WinePrefix.fromJson(Map<String, dynamic> json) {
    PrefixType type;
    final typeString = json['type'] as String?;
    if (typeString == 'PrefixType.proton') {
      type = PrefixType.proton;
    } else if (typeString == 'PrefixType.gaming' || typeString == 'PrefixType.custom') { 
      // Convert both "gaming" and "custom" to wine for backward compatibility
      type = PrefixType.wine;
    } else {
      type = PrefixType.wine; // Default to wine
    }

    // Parse environment variables if present
    Map<String, String> envVars = {};
    final rawEnvVars = json['environmentVariables'];
    if (rawEnvVars != null && rawEnvVars is Map) {
      rawEnvVars.forEach((key, value) {
        if (key is String && value is String) {
          envVars[key] = value;
        }
      });
    }

    return WinePrefix(
      name: json['name'],
      path: json['path'],
      wineBuildPath: json['wineBuildPath'],
      type: type, // Use parsed type
      architecture: json['architecture'] as String? ?? 'win64', // Added from JSON, default to win64 if missing
      exeEntries: (json['exeEntries'] as List)
          .map((e) => ExeEntry.fromJson(e))
          .toList(),
      environmentVariables: envVars, // Add environment variables
    );
  }

  WinePrefix copyWith({
    String? name,
    String? path,
    String? wineBuildPath,
    PrefixType? type,
    List<ExeEntry>? exeEntries,
    String? architecture, // Added to copyWith
    Map<String, String>? environmentVariables,
  }) {
    return WinePrefix(
      name: name ?? this.name,
      path: path ?? this.path,
      wineBuildPath: wineBuildPath ?? this.wineBuildPath,
      type: type ?? this.type,
      exeEntries: exeEntries ?? this.exeEntries,
      architecture: architecture ?? this.architecture, // Added to copyWith
      environmentVariables: environmentVariables ?? this.environmentVariables,
    );
  }
}

class ExeEntry {
  final String path;
  final String name;
  final int? igdbId;
  final int? steamAppId;
  final String? coverUrl; // Fetched/Constructed URL
  final String? coverImageId; // Fetched image_id for cover
  final int? igdbCoverId; // Raw cover ID from IGDB search
  final String? localCoverPath;
  final List<String> screenshotUrls; // Fetched/Constructed URLs
  final List<String> screenshotImageIds; // Fetched image_ids for screenshots
  final List<int> igdbScreenshotIds; // Raw screenshot IDs from IGDB search
  final List<String> localScreenshotPaths;

  final List<String> videoIds; // YouTube video IDs
  final bool isGame;
  final String? description;
  final bool notWorking;
  final String? category;
  final PrefixType? wineTypeOverride;
  final String? launchOptions;
  final int? playTimeMinutes; // Total play time in minutes
  final DateTime? lastPlayed; // Last time the game was played

  const ExeEntry({
    required this.path,
    required this.name,
    this.igdbId,
    this.steamAppId,
    this.coverUrl,
    this.coverImageId,
    this.igdbCoverId, // Add to constructor
    this.localCoverPath,
    this.screenshotUrls = const [],
    this.screenshotImageIds = const [],
    this.igdbScreenshotIds = const [], // Add to constructor
    this.localScreenshotPaths = const [],
    this.videoIds = const [],
    this.isGame = false,
    this.description,
    this.notWorking = false,
    this.category,
    this.wineTypeOverride,
    this.launchOptions,
    this.playTimeMinutes = 0,
    this.lastPlayed,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'igdbId': igdbId,
    'steamAppId': steamAppId,
    'coverUrl': coverUrl,
    'coverImageId': coverImageId,
    'igdbCoverId': igdbCoverId, // Add to JSON
    'localCoverPath': localCoverPath,
    'screenshotUrls': screenshotUrls,
    'screenshotImageIds': screenshotImageIds,
    'igdbScreenshotIds': igdbScreenshotIds, // Add to JSON
    'localScreenshotPaths': localScreenshotPaths,
    'videoIds': videoIds,
    'isGame': isGame,
    'description': description,
    'notWorking': notWorking,
    'category': category,
    'wineTypeOverride': wineTypeOverride?.toString(),
    'launchOptions': launchOptions,
    'playTimeMinutes': playTimeMinutes,
    'lastPlayed': lastPlayed?.toIso8601String(),
  };

  factory ExeEntry.fromJson(Map<String, dynamic> json) {
     PrefixType? overrideType;
     final overrideTypeString = json['wineTypeOverride'] as String?;
     if (overrideTypeString != null) {
        if (overrideTypeString == 'PrefixType.proton') {
           overrideType = PrefixType.proton;
        // } else if (overrideTypeString == 'PrefixType.protonExperimental') { // Removed handling
        //    overrideType = PrefixType.protonExperimental;
        } else if (overrideTypeString == 'PrefixType.wine') {
           overrideType = PrefixType.wine;
        } else if (overrideTypeString == 'PrefixType.gaming') { // Handle Gaming type
           overrideType = PrefixType.wine;
        }
     }

     return ExeEntry(
        path: json['path'],
        name: json['name'],
        igdbId: json['igdbId'],
        steamAppId: json['steamAppId'],
        coverUrl: json['coverUrl'],
        coverImageId: json['coverImageId'],
        igdbCoverId: json['igdbCoverId'], // Read from JSON
        localCoverPath: json['localCoverPath'],
        screenshotUrls: json['screenshotUrls'] != null
            ? List<String>.from(json['screenshotUrls'])
            : [],
        screenshotImageIds: json['screenshotImageIds'] != null
            ? List<String>.from(json['screenshotImageIds'])
            : [],
        igdbScreenshotIds: json['igdbScreenshotIds'] != null // Read from JSON
            ? List<int>.from(json['igdbScreenshotIds'])
            : [],
        localScreenshotPaths: json['localScreenshotPaths'] != null
            ? List<String>.from(json['localScreenshotPaths'])
            : [],
        videoIds: json['videoIds'] != null
            ? List<String>.from(json['videoIds'])
            : [],
        isGame: json['isGame'] ?? false,
        description: json['description'],
        notWorking: json['notWorking'] ?? false,
        category: json['category'],
        wineTypeOverride: overrideType, // Use parsed override type
        launchOptions: json['launchOptions'],
        playTimeMinutes: json['playTimeMinutes']?.toInt() ?? 0, // Parse playTimeMinutes
        lastPlayed: json['lastPlayed'] != null
            ? DateTime.parse(json['lastPlayed'])
            : null, // Parse lastPlayed as DateTime
     );
  }

  ExeEntry copyWith({
    String? path,
    String? name,
    int? igdbId,
    int? steamAppId,
    String? coverUrl,
    String? coverImageId,
    int? igdbCoverId,
    String? localCoverPath,
    List<String>? screenshotUrls,
    List<String>? screenshotImageIds,
    List<int>? igdbScreenshotIds,
    List<String>? localScreenshotPaths,
    List<String>? videoIds,
    bool? isGame,
    String? description,
    bool? notWorking,
    String? category,
    PrefixType? wineTypeOverride,
    String? launchOptions,
    int? playTimeMinutes,
    DateTime? lastPlayed,
  }) {
    return ExeEntry(
      path: path ?? this.path,
      name: name ?? this.name,
      igdbId: igdbId ?? this.igdbId,
      steamAppId: steamAppId ?? this.steamAppId,
      coverUrl: coverUrl ?? this.coverUrl,
      coverImageId: coverImageId ?? this.coverImageId,
      igdbCoverId: igdbCoverId ?? this.igdbCoverId,
      localCoverPath: localCoverPath ?? this.localCoverPath,
      screenshotUrls: screenshotUrls ?? this.screenshotUrls,
      screenshotImageIds: screenshotImageIds ?? this.screenshotImageIds,
      igdbScreenshotIds: igdbScreenshotIds ?? this.igdbScreenshotIds,
      localScreenshotPaths: localScreenshotPaths ?? this.localScreenshotPaths,
      videoIds: videoIds ?? this.videoIds,
      isGame: isGame ?? this.isGame,
      description: description ?? this.description,
      notWorking: notWorking ?? this.notWorking,
      category: category ?? this.category,
      wineTypeOverride: wineTypeOverride ?? this.wineTypeOverride,
      launchOptions: launchOptions ?? this.launchOptions,
      playTimeMinutes: playTimeMinutes ?? this.playTimeMinutes,
      lastPlayed: lastPlayed ?? this.lastPlayed,
    );
  }
}

class GameEntry {
  final WinePrefix prefix;
  final ExeEntry exe;

  const GameEntry({
    required this.prefix,
    required this.exe,
  });
}
