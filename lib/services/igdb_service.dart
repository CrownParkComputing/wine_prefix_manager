import 'dart:convert';
import 'package:flutter/foundation.dart'; // For debugPrint (used carefully)
import 'package:http/http.dart' as http;
import '../models/settings.dart';
import '../models/igdb_models.dart';

class IgdbService {

  Future<Map<String, dynamic>?> getIgdbToken(Settings settings) async {
    if (settings.igdbClientId.isEmpty || settings.igdbClientSecret.isEmpty) {
      debugPrint('IGDB credentials not set.');
      return null;
    }

    if (settings.igdbAccessToken != null &&
        settings.igdbTokenExpiry != null &&
        settings.igdbTokenExpiry!.isAfter(DateTime.now())) {
      return {
        'token': settings.igdbAccessToken!,
        'expiry': settings.igdbTokenExpiry!,
        'isNew': false,
      };
    }

    debugPrint('Fetching new IGDB token...');
    try {
      final response = await http.post(
        Uri.parse(settings.twitchOAuthUrl), // Use settings URL
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
        debugPrint('Successfully fetched new IGDB token.');
        return {
          'token': token,
          'expiry': expiryTime,
          'isNew': true,
        };
      } else {
        debugPrint('Failed to get IGDB token: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Error getting IGDB token: $e');
    }
    return null;
  }

  Future<List<IgdbGame>> searchIgdbGames(String query, Settings settings, String token) async {
    try {
      final response = await http.post(
        Uri.parse(settings.igdbApiBaseUrl).replace(path: '/v4/games'), // Use replace
        headers: {
          'Accept': 'application/json',
          'Client-ID': settings.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        body: 'search "$query"; fields name,cover,screenshots,videos,summary; where platforms = (6); limit 20;',
      );

      if (response.statusCode == 200) {
        final List<dynamic> games = json.decode(response.body);
        return games.map((g) => IgdbGame.fromJson(g)).toList();
      } else {
        debugPrint('IGDB API error during search: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Error searching IGDB: $e');
    }
    return [];
  }

  Future<Map<String, String>?> fetchCoverDetails(int? coverId, Settings settings, String token) async {
    if (coverId == null) return null;
    try {
      final response = await http.post(
        Uri.parse(settings.igdbApiBaseUrl).replace(path: '/v4/covers'), // Use replace
        headers: {
          'Accept': 'application/json',
          'Client-ID': settings.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        body: 'fields image_id, url; where id = $coverId;', // Request URL field too
      );

      // debugPrint("IGDB Cover Request Body: ${'fields image_id, url; where id = $coverId;'}"); // Keep commented
      if (response.statusCode == 200) {
        // debugPrint("IGDB Cover Response Body: ${response.body}"); // Keep commented
        final List<dynamic> covers = json.decode(response.body);
        if (covers.isNotEmpty) {
          final coverData = covers[0];
          final imageId = coverData['image_id']?.toString();
          String? imageUrl = coverData['url']?.toString();

          if (imageUrl != null && imageUrl.isNotEmpty) {
             if (imageUrl.startsWith('//')) {
               imageUrl = 'https:$imageUrl';
             }
             imageUrl = imageUrl.replaceFirst('/t_thumb/', '/t_cover_big/');
             // debugPrint("Using direct URL from API for cover: $imageUrl"); // Keep commented
             return {'url': imageUrl, 'imageId': imageId ?? ''};
          } else if (imageId != null) {
             // debugPrint("Constructing cover URL from imageId as 'url' field was missing."); // Keep commented
             imageUrl = '${settings.igdbImageBaseUrl}/t_cover_big/$imageId.jpg';
             return {'url': imageUrl, 'imageId': imageId};
          }
        }
      } else {
         debugPrint('IGDB API error fetching cover: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Error fetching cover: $e');
    }
    return null;
  }

  Future<List<Map<String, String>>> fetchScreenshotDetails(List<int> screenshotIds, Settings settings, String token) async {
    if (screenshotIds.isEmpty) return [];
    try {
      final requestBody = 'fields image_id, url; where id = (${screenshotIds.join(",")}); limit ${screenshotIds.length};';
      // debugPrint("IGDB Screenshot Request Body: $requestBody"); // Keep commented
      final response = await http.post(
        Uri.parse(settings.igdbApiBaseUrl).replace(path: '/v4/screenshots'), // Use replace
        headers: {
          'Accept': 'application/json',
          'Client-ID': settings.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        body: requestBody,
      );

      if (response.statusCode == 200) {
        // debugPrint("IGDB Screenshot Response Body: ${response.body}"); // Keep commented
        final List<dynamic> screenshots = json.decode(response.body);
        List<Map<String, String>> results = [];
        for (var s in screenshots) {
          final imageId = s['image_id']?.toString();
          String? imageUrl = s['url']?.toString();

          if (imageUrl != null && imageUrl.isNotEmpty) {
             if (imageUrl.startsWith('//')) {
               imageUrl = 'https:$imageUrl';
             }
             imageUrl = imageUrl.replaceFirst('/t_thumb/', '/t_screenshot_big/');
             // debugPrint("Using direct URL from API for screenshot: $imageUrl"); // Keep commented
             results.add({'url': imageUrl, 'imageId': imageId ?? ''});
          } else if (imageId != null) {
             // debugPrint("Constructing screenshot URL from imageId as 'url' field was missing."); // Keep commented
             imageUrl = '${settings.igdbImageBaseUrl}/t_screenshot_big/$imageId.jpg';
             results.add({'url': imageUrl, 'imageId': imageId});
          }
        }
        return results;
      } else {
        debugPrint('IGDB API error fetching screenshots: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Error fetching screenshots: $e');
    }
    return [];
  }

  Future<List<String>> fetchGameVideoIds(int gameId, Settings settings, String token) async {
    try {
      final response = await http.post(
        Uri.parse(settings.igdbApiBaseUrl).replace(path: '/v4/game_videos'), // Use replace
        headers: {
          'Accept': 'application/json',
          'Client-ID': settings.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        body: 'fields video_id; where game = $gameId;',
      );

      if (response.statusCode == 200) {
        final List<dynamic> videos = json.decode(response.body);
        return videos.map((v) => v['video_id'].toString()).toList();
      } else {
        debugPrint('IGDB API error fetching videos: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Exception fetching game videos: $e');
    }
    return [];
  }
}