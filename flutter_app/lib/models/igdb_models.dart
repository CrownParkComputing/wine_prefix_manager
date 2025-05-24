class IgdbGame {
  final int id;
  final String name;
  final String? summary;
  final int? cover;
  final List<int> screenshots;
  final List<int> videos;  // Add videos field

  IgdbGame({
    required this.id,
    required this.name,
    this.summary,
    this.cover,
    this.screenshots = const [],
    this.videos = const [],  // Initialize videos field
  });

  factory IgdbGame.fromJson(Map<String, dynamic> json) {
    return IgdbGame(
      id: json['id'],
      name: json['name'],
      summary: json['summary'],
      cover: json['cover'],
      screenshots: json['screenshots'] != null
          ? List<int>.from(json['screenshots'])
          : [],
      videos: json['videos'] != null
          ? List<int>.from(json['videos'])
          : [],  // Parse videos from JSON
    );
  }
}

class IgdbCover {
  final int id;
  final String imageId;
  final int gameId;

  IgdbCover({
    required this.id,
    required this.imageId,
    required this.gameId,
  });

  factory IgdbCover.fromJson(Map<String, dynamic> json) {
    return IgdbCover(
      id: json['id'],
      imageId: json['image_id'],
      gameId: json['game'],
    );
  }

  String get url => 'https://images.igdb.com/igdb/image/upload/t_cover_big/$imageId.jpg';
}

class IgdbScreenshot {
  final int id;
  final String imageId;
  final int gameId;

  IgdbScreenshot({
    required this.id,
    required this.imageId,
    required this.gameId,
  });

  factory IgdbScreenshot.fromJson(Map<String, dynamic> json) {
    return IgdbScreenshot(
      id: json['id'],
      imageId: json['image_id'],
      gameId: json['game'],
    );
  }

  String get url => 'https://images.igdb.com/igdb/image/upload/t_screenshot_big/$imageId.jpg';
}

// Add a new class for game videos
class IgdbGameVideo {
  final int id;
  final String videoId;
  final String name;
  final int gameId;

  IgdbGameVideo({
    required this.id,
    required this.videoId,
    required this.name,
    required this.gameId,
  });

  factory IgdbGameVideo.fromJson(Map<String, dynamic> json) {
    return IgdbGameVideo(
      id: json['id'],
      videoId: json['video_id'],
      name: json['name'],
      gameId: json['game'],
    );
  }

  String get youtubeUrl => 'https://www.youtube.com/watch?v=$videoId';
  String get thumbnailUrl => 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
}
