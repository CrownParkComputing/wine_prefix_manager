import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/settings.dart'; // Adjust import path as needed
import '../models/igdb_models.dart'; // Adjust import path as needed

class IgdbService {
  // Note: This service now requires the Settings object to be passed in.
  // Consider using a dependency injection solution or passing it to the constructor
  // if the service instance lives longer.

  /// Fetches or retrieves a valid IGDB API token.
  /// Returns a Map containing 'token' and 'expiry' if successful, otherwise null.
  Future<Map<String, dynamic>?> getIgdbToken(Settings settings) async {
    if (settings.igdbClientId.isEmpty || settings.igdbClientSecret.isEmpty) {
      print('IGDB credentials not set.');
      return null;
    }

    // Check if we have a valid token already
    if (settings.igdbAccessToken != null &&
        settings.igdbTokenExpiry != null &&
        settings.igdbTokenExpiry!.isAfter(DateTime.now())) {
      // Return existing valid token and its expiry
      return {
        'token': settings.igdbAccessToken!,
        'expiry': settings.igdbTokenExpiry!,
        'isNew': false, // Indicate it's not a newly fetched token
      };
    }

    // Fetch a new token
    print('Fetching new IGDB token...');
    try {
      final response = await http.post(
        Uri.parse('https://id.twitch.tv/oauth2/token'),
        body: {
          'client_id': settings.igdbClientId,
          'client_secret': settings.igdbClientSecret,
          'grant_type': 'client_credentials',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['access_token'] as String;
        final expiresIn = Duration(seconds: data['expires_in'] as int);
        final expiryTime = DateTime.now().add(expiresIn);

        print('Successfully fetched new IGDB token.');
        return {
          'token': token,
          'expiry': expiryTime,
          'isNew': true, // Indicate it's a newly fetched token
        };
      } else {
        print('Failed to get IGDB token: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error getting IGDB token: $e');
    }
    return null;
  }

  Future<List<IgdbGame>> searchIgdbGames(String query, Settings settings, String token) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.igdb.com/v4/games'),
        headers: {
          'Accept': 'application/json',
          'Client-ID': settings.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        // Query adjusted slightly for clarity
        body: 'search "$query"; fields name,cover,screenshots,videos,summary; where platforms = (6); limit 20;',
      );

      if (response.statusCode == 200) {
        final List<dynamic> games = json.decode(response.body);
        return games.map((g) => IgdbGame.fromJson(g)).toList();
      } else {
        print('IGDB API error during search: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error searching IGDB: $e');
    }
    return [];
  }

  Future<String?> fetchCoverUrl(int? coverId, Settings settings, String token) async {
    if (coverId == null) return null;

    try {
      final response = await http.post(
        Uri.parse('https://api.igdb.com/v4/covers'),
        headers: {
          'Accept': 'application/json',
          'Client-ID': settings.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        body: 'fields image_id; where id = $coverId;',
      );

      if (response.statusCode == 200) {
        final List<dynamic> covers = json.decode(response.body);
        if (covers.isNotEmpty) {
          final imageId = covers[0]['image_id'];
          // Using a recommended size, adjust as needed
          return 'https://images.igdb.com/igdb/image/upload/t_cover_big/$imageId.jpg';
        }
      } else {
         print('IGDB API error fetching cover: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error fetching cover: $e');
    }
    return null;
  }

  Future<List<String>> fetchScreenshotUrls(List<int> screenshotIds, Settings settings, String token) async {
    if (screenshotIds.isEmpty) return [];

    try {
      final response = await http.post(
        Uri.parse('https://api.igdb.com/v4/screenshots'),
        headers: {
          'Accept': 'application/json',
          'Client-ID': settings.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        body: 'fields image_id; where id = (${screenshotIds.join(",")}); limit ${screenshotIds.length};', // Added limit
      );

      if (response.statusCode == 200) {
        final List<dynamic> screenshots = json.decode(response.body);
        return screenshots
          // Using a recommended size, adjust as needed
          .map((s) => 'https://images.igdb.com/igdb/image/upload/t_screenshot_big/${s["image_id"]}.jpg')
          .toList();
      } else {
        print('IGDB API error fetching screenshots: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error fetching screenshots: $e');
    }
    return [];
  }

  Future<List<String>> fetchGameVideoIds(int gameId, Settings settings, String token) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.igdb.com/v4/game_videos'),
        headers: {
          'Accept': 'application/json',
          'Client-ID': settings.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        body: 'fields video_id; where game = $gameId;', // Simplified fields
      );

      if (response.statusCode == 200) {
        final List<dynamic> videos = json.decode(response.body);
        return videos.map((v) => v['video_id'].toString()).toList();
      } else {
        print('IGDB API error fetching videos: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Exception fetching game videos: $e');
    }
    return [];
  }
}