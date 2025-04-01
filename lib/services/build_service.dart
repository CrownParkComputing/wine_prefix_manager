import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/wine_build.dart'; // Adjust import path as needed
import '../models/settings.dart'; // Import Settings model

class BuildService {
  Future<List<BaseBuild>> fetchBuilds(Settings? settings) async {
    if (settings == null) {
      throw Exception('Settings not initialized');
    }
    
    // Remove the specific property check since the property name is unknown
    // Instead, let's try to fetch using whatever URL property is available in the settings
    
    try {
      final String url = '${settings.buildsApiUrl}/api/v1/builds'; // Use the correct property name

      List<BaseBuild> builds = [];

      // Fetch Wine builds
      final wineResponse = await http.get(Uri.parse(settings.wineBuildsApiUrl)); // Use settings URL

      if (wineResponse.statusCode == 200) {
        final wineData = json.decode(wineResponse.body);
        final wineAssets = wineData['assets'] as List;

        builds.addAll(
          wineAssets
              .where((asset) => asset['name'].toString().endsWith('.tar.xz'))
              .map((asset) => WineBuild.fromGitHubAsset(asset, '10.4'))
              .toList()
        );
      } else {
        print('Failed to fetch Wine builds: ${wineResponse.statusCode}');
        // Optionally throw an exception or return partial results
      }

      // Fetch Proton builds
      final protonResponse = await http.get(Uri.parse(settings.protonGeApiUrl)); // Use settings URL

      if (protonResponse.statusCode == 200) {
        final List<dynamic> releases = json.decode(protonResponse.body);
        builds.addAll(
          releases
              .take(5) // Only get the latest 5 releases
              .map((release) => ProtonBuild.fromGitHubRelease(release))
              .toList()
        );
      } else {
        print('Failed to fetch Proton builds: ${protonResponse.statusCode}');
        // Optionally throw an exception or return partial results
      }

      return builds;
    } catch (e) {
      throw Exception('Error fetching builds: ${e.toString()}. Check your settings configuration.');
    }
  }
}