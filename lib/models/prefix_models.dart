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

  WinePrefix copyWith({
    String? name,
    String? path,
    String? wineBuildPath,
    PrefixType? type,
    List<ExeEntry>? exeEntries,
  }) {
    return WinePrefix(
      name: name ?? this.name,
      path: path ?? this.path,
      wineBuildPath: wineBuildPath ?? this.wineBuildPath,
      type: type ?? this.type,
      exeEntries: exeEntries ?? this.exeEntries,
    );
  }
}

class ExeEntry {
  final String path;
  final String name;
  final int? igdbId;
  final String? coverUrl; // Original URL from IGDB
  final String? coverImageId; // Raw image_id for cover

  final String? localCoverPath; // Path to locally stored cover
  final List<String> screenshotUrls; // Original URLs from IGDB
  final List<String> localScreenshotPaths; // Paths to locally stored screenshots
  final List<String> screenshotImageIds; // Raw image_ids for screenshots

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
    this.coverImageId, // Add new field
    this.localCoverPath,
    this.screenshotUrls = const [],
    this.screenshotImageIds = const [], // Add new field
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
    'coverImageId': coverImageId, // Add new field
    'localCoverPath': localCoverPath,
    'screenshotUrls': screenshotUrls,
    'screenshotImageIds': screenshotImageIds, // Add new field
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
    coverImageId: json['coverImageId'], // Add new field
    localCoverPath: json['localCoverPath'],
    screenshotUrls: json['screenshotUrls'] != null
        ? List<String>.from(json['screenshotUrls'])
        : [],
    screenshotImageIds: json['screenshotImageIds'] != null // Add new field
        ? List<String>.from(json['screenshotImageIds'])
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

  ExeEntry copyWith({
    String? path,
    String? name,
    int? igdbId,
    String? coverUrl,
    String? coverImageId, // Add new field
    String? localCoverPath,
    List<String>? screenshotUrls,
    List<String>? screenshotImageIds, // Add new field
    List<String>? localScreenshotPaths,
    List<String>? videoIds,
    bool? isGame,
    String? description,
    bool? notWorking,
    String? category,
    PrefixType? wineTypeOverride,
  }) {
    return ExeEntry(
      path: path ?? this.path,
      name: name ?? this.name,
      igdbId: igdbId ?? this.igdbId,
      coverUrl: coverUrl ?? this.coverUrl,
      coverImageId: coverImageId ?? this.coverImageId, // Add new field
      localCoverPath: localCoverPath ?? this.localCoverPath,
      screenshotUrls: screenshotUrls ?? this.screenshotUrls,
      screenshotImageIds: screenshotImageIds ?? this.screenshotImageIds, // Add new field
      localScreenshotPaths: localScreenshotPaths ?? this.localScreenshotPaths,
      videoIds: videoIds ?? this.videoIds,
      isGame: isGame ?? this.isGame,
      description: description ?? this.description,
      notWorking: notWorking ?? this.notWorking,
      category: category ?? this.category,
      wineTypeOverride: wineTypeOverride ?? this.wineTypeOverride,
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
