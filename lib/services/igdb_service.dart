import 'dart:convert';
// import 'package:flutter/foundation.dart'; // Unused import removed
import 'package:http/http.dart' as http;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';
import '../models/igdb_models.dart';
import '../providers/settings_provider.dart';

class IgdbService {

  Future<Map<String, dynamic>?> getIgdbToken(Settings settings) async {
    if (settings.igdbClientId.isEmpty || settings.igdbClientSecret.isEmpty) {
      // debugPrint('[IgdbService] IGDB credentials not set.');
      return null;
    }

    if (settings.igdbAccessToken != null &&
        settings.igdbTokenExpiry != null &&
        settings.igdbTokenExpiry!.isAfter(DateTime.now())) {
       // debugPrint('[IgdbService] Using existing IGDB token.');
      return {
        'token': settings.igdbAccessToken!,
        'expiry': settings.igdbTokenExpiry!,
        'isNew': false,
      };
    }

    // debugPrint('[IgdbService] Fetching new IGDB token...');
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
        // debugPrint('[IgdbService] Successfully fetched new IGDB token.');
        return {
          'token': token,
          'expiry': expiryTime,
          'isNew': true,
        };
      } else {
        // debugPrint('[IgdbService] Failed to get IGDB token: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      // debugPrint('[IgdbService] Error getting IGDB token: $e');
    }
    return null;
  }

  Future<List<IgdbGame>> searchIgdbGames(String query, Settings settings, String token) async {
    // debugPrint('[IgdbService] Searching IGDB for: "$query"');
    final String requestBody = 'search "$query"; fields name,cover,screenshots,videos,summary; where platforms = (6); limit 20;'; // PC platform = 6
    // debugPrint('[IgdbService] Request Body: $requestBody');
    try {
      final response = await http.post(
        Uri.parse(settings.igdbApiBaseUrl).replace(path: '/v4/games'), // Use replace
        headers: {
          'Accept': 'application/json',
          'Client-ID': settings.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        body: requestBody,
      );

      // debugPrint('[IgdbService] Search Response Status: ${response.statusCode}');
      // Added logging for raw response body
      // debugPrint('[IgdbService] Search Response Body Raw: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> gamesJson = json.decode(response.body);
        // debugPrint('[IgdbService] Parsed ${gamesJson.length} games from JSON.');
        // Add detailed logging for each parsed game
        final gamesList = gamesJson.map((g) {
           // debugPrint('[IgdbService] Parsing game JSON: $g');
           final igdbGame = IgdbGame.fromJson(g);
           // debugPrint('[IgdbService] Parsed IgdbGame: id=${igdbGame.id}, name=${igdbGame.name}, cover=${igdbGame.cover}, screenshots=${igdbGame.screenshots}');
           return igdbGame;
        }).toList();
        return gamesList;
      } else {
        // debugPrint('[IgdbService] IGDB API error during search: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      // debugPrint('[IgdbService] Error searching IGDB: $e');
    }
    return [];
  }

  Future<Map<String, String>?> fetchCoverDetails(int? coverId, Settings settings, String token) async {
    if (coverId == null) return null;
    // debugPrint('[IgdbService] Fetching cover details for ID: $coverId');
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

      if (response.statusCode == 200) {
        final List<dynamic> covers = json.decode(response.body);
        if (covers.isNotEmpty) {
          final coverData = covers[0];
          final imageId = coverData['image_id']?.toString();
          String? imageUrl = coverData['url']?.toString();
          // debugPrint('[IgdbService] Cover API Response Data: $coverData');

          if (imageUrl != null && imageUrl.isNotEmpty) {
             if (imageUrl.startsWith('//')) {
               imageUrl = 'https:$imageUrl';
             }
             imageUrl = imageUrl.replaceFirst('/t_thumb/', '/t_cover_big/');
             // debugPrint("[IgdbService] Using direct URL from API for cover: $imageUrl");
             return {'url': imageUrl, 'imageId': imageId ?? ''};
          } else if (imageId != null) {
             // debugPrint("[IgdbService] Constructing cover URL from imageId as 'url' field was missing.");
             imageUrl = '${settings.igdbImageBaseUrl}/t_cover_big/$imageId.jpg';
             return {'url': imageUrl, 'imageId': imageId};
          } else {
             // debugPrint("[IgdbService] Cover details fetched but no URL or imageId found.");
          }
        } else {
           // debugPrint("[IgdbService] Cover details fetched but response list was empty for ID: $coverId");
        }
      } else {
         // debugPrint('[IgdbService] IGDB API error fetching cover: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      // debugPrint('[IgdbService] Error fetching cover: $e');
    }
    return null;
  }

  Future<List<Map<String, String>>> fetchScreenshotDetails(List<int> screenshotIds, Settings settings, String token) async {
    if (screenshotIds.isEmpty) return [];
    // debugPrint('[IgdbService] Fetching screenshot details for IDs: $screenshotIds');
    try {
      final requestBody = 'fields image_id, url; where id = (${screenshotIds.join(",")}); limit ${screenshotIds.length};';
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
        final List<dynamic> screenshots = json.decode(response.body);
        // debugPrint('[IgdbService] Screenshot API Response Data: $screenshots');
        List<Map<String, String>> results = [];
        for (var s in screenshots) {
          final imageId = s['image_id']?.toString();
          String? imageUrl = s['url']?.toString();

          if (imageUrl != null && imageUrl.isNotEmpty) {
             if (imageUrl.startsWith('//')) {
               imageUrl = 'https:$imageUrl';
             }
             imageUrl = imageUrl.replaceFirst('/t_thumb/', '/t_screenshot_big/');
             // debugPrint("[IgdbService] Using direct URL from API for screenshot: $imageUrl");
             results.add({'url': imageUrl, 'imageId': imageId ?? ''});
          } else if (imageId != null) {
             // debugPrint("[IgdbService] Constructing screenshot URL from imageId as 'url' field was missing.");
             imageUrl = '${settings.igdbImageBaseUrl}/t_screenshot_big/$imageId.jpg';
             results.add({'url': imageUrl, 'imageId': imageId});
          } else {
             // debugPrint("[IgdbService] Screenshot details fetched but no URL or imageId found for item: $s");
          }
        }
        return results;
      } else {
        // debugPrint('[IgdbService] IGDB API error fetching screenshots: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      // debugPrint('[IgdbService] Error fetching screenshots: $e');
    }
    return [];
  }

  Future<List<String>> fetchGameVideoIds(int gameId, Settings settings, String token) async {
     // debugPrint('[IgdbService] Fetching video IDs for game ID: $gameId');
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
        // debugPrint('[IgdbService] Video API Response Data: $videos');
        return videos.map((v) => v['video_id'].toString()).toList();
      } else {
        // debugPrint('[IgdbService] IGDB API error fetching videos: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      // debugPrint('[IgdbService] Exception fetching game videos: $e');
    }
    return [];
  }

  // Method to check and validate IGDB credentials
  Future<bool> validateCredentials(BuildContext context) async {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final settings = settingsProvider.settings;
    
    // Check if credentials are set
    if (settings.igdbClientId.isEmpty || settings.igdbClientSecret.isEmpty) {
      return false;
    }
    
    try {
      final tokenData = await getIgdbToken(settings);
      if (tokenData != null && tokenData['token'] != null) {
        // If token is new, update it in settings
        if (tokenData['isNew'] == true) {
          await settingsProvider.updateIgdbToken(
            tokenData['token'], 
            tokenData['expiry'].difference(DateTime.now()),
          );
        }
        return true;
      }
    } catch (e) {
      // Token retrieval failed
      return false;
    }
    
    return false;
  }
}