import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/wine_build.dart'; // Adjust import path as needed

class BuildService {
  Future<List<BaseBuild>> fetchBuilds() async {
    List<BaseBuild> builds = [];

    try {
      // Fetch Wine builds
      final wineResponse = await http.get(Uri.parse(
          'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.4'));

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
      final protonResponse = await http.get(Uri.parse(
          'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases'));

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
    } catch (e) {
      print('Error fetching builds: $e');
      // Rethrow or handle as appropriate for your error handling strategy
      rethrow;
    }

    return builds;
  }
}