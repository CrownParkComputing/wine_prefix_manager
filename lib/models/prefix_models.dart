import 'package:flutter/material.dart';

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

  const WinePrefix({
    required this.name,
    required this.path,
    required this.wineBuildPath,
    required this.type,
    required this.exeEntries,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'wineBuildPath': wineBuildPath,
    'type': type.toString(),
    'exeEntries': exeEntries.map((e) => e.toJson()).toList(),
  };

  factory WinePrefix.fromJson(Map<String, dynamic> json) => WinePrefix(
    name: json['name'],
    path: json['path'],
    wineBuildPath: json['wineBuildPath'],
    type: json['type'] == 'PrefixType.proton' ? PrefixType.proton : PrefixType.wine,
    exeEntries: (json['exeEntries'] as List)
        .map((e) => ExeEntry.fromJson(e))
        .toList(),
  );
}

class ExeEntry {
  final String path;
  final String name;
  final int? igdbId;
  final String? coverUrl; // Original URL from IGDB
  final String? localCoverPath; // Path to locally stored cover
  final List<String> screenshotUrls; // Original URLs from IGDB
  final List<String> localScreenshotPaths; // Paths to locally stored screenshots
  final List<String> videoIds;
  final bool isGame;
  final String? description;
  final bool notWorking;
  final String? category;
  final PrefixType? wineTypeOverride;

  const ExeEntry({
    required this.path,
    required this.name,
    this.igdbId,
    this.coverUrl,
    this.localCoverPath,
    this.screenshotUrls = const [],
    this.localScreenshotPaths = const [],
    this.videoIds = const [],
    this.isGame = false,
    this.description,
    this.notWorking = false,
    this.category,
    this.wineTypeOverride,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'igdbId': igdbId,
    'coverUrl': coverUrl,
    'localCoverPath': localCoverPath,
    'screenshotUrls': screenshotUrls,
    'localScreenshotPaths': localScreenshotPaths,
    'videoIds': videoIds,
    'isGame': isGame,
    'description': description,
    'notWorking': notWorking,
    'category': category,
    'wineTypeOverride': wineTypeOverride?.toString(),
  };

  factory ExeEntry.fromJson(Map<String, dynamic> json) => ExeEntry(
    path: json['path'],
    name: json['name'],
    igdbId: json['igdbId'],
    coverUrl: json['coverUrl'],
    localCoverPath: json['localCoverPath'],
    screenshotUrls: json['screenshotUrls'] != null
        ? List<String>.from(json['screenshotUrls'])
        : [],
    localScreenshotPaths: json['localScreenshotPaths'] != null // Add this block
        ? List<String>.from(json['localScreenshotPaths'])
        : [],
    videoIds: json['videoIds'] != null
        ? List<String>.from(json['videoIds']) 
        : [],
    isGame: json['isGame'] ?? false,
    description: json['description'],
    notWorking: json['notWorking'] ?? false,
    category: json['category'],
    wineTypeOverride: json['wineTypeOverride'] != null
        ? PrefixType.values.firstWhere(
            (e) => e.toString() == json['wineTypeOverride'],
            orElse: () => PrefixType.wine,
          )
        : null,
  );
}

class GameEntry {
  final WinePrefix prefix;
  final ExeEntry exe;
  
  const GameEntry({
    required this.prefix, 
    required this.exe,
  });
}
