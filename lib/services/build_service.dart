import 'dart:convert';
import 'dart:io'; // Added for Directory/File operations
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p; // Added for path manipulation
import '../models/wine_build.dart';
import '../models/settings.dart';
import '../models/prefix_models.dart'; // Import PrefixType

class BuildService {

  /// Parses Steam's libraryfolders.vdf to find library paths.
  Future<List<String>> _getSteamLibraryPaths(String steamRootPath) async {
    // Look for VDF in root/steamapps and root itself
    final List<String> potentialVdfPaths = [
      p.join(steamRootPath, 'steamapps', 'libraryfolders.vdf'),
      p.join(steamRootPath, 'libraryfolders.vdf'),
    ];
    File? vdfFile;
    String? foundVdfPath;

    for (final vdfPath in potentialVdfPaths) {
       final file = File(vdfPath);
       if (await file.exists()) {
          vdfFile = file;
          foundVdfPath = vdfPath;
          break;
       }
    }

    List<String> libraryPaths = [];

    // Always add the default library path relative to the steam root if it exists
    final defaultLibraryPath = p.join(steamRootPath);
    // Check for steamapps dir as a sign of a valid library root
    if (await Directory(p.join(defaultLibraryPath, 'steamapps')).exists()) {
       libraryPaths.add(defaultLibraryPath);
    } else {
       // Default library path steamapps not found
    }

    if (vdfFile != null && foundVdfPath != null) {
      try {
        final content = await vdfFile.readAsString();
        final regex = RegExp(r'"\d+"\s*{\s*"path"\s*"([^"]+)"', multiLine: true);
        final matches = regex.allMatches(content);


        for (final match in matches) {
          if (match.groupCount >= 1) {
            final libraryPath = match.group(1);
            if (libraryPath != null && libraryPath.isNotEmpty) {
              final absolutePath = p.isAbsolute(libraryPath) ? libraryPath : p.join(p.dirname(foundVdfPath), libraryPath);
              final libraryDir = Directory(absolutePath);
              final steamappsDir = Directory(p.join(absolutePath, 'steamapps'));

              if (await libraryDir.exists() && await steamappsDir.exists()) {
                 libraryPaths.add(absolutePath);
              } else {
                 // VDF library path invalid or missing steamapps
              }
            }
          }
        }
      } catch (e) {
        // Error reading or parsing libraryfolders.vdf
      }
    } else {
       // libraryfolders.vdf not found in checked locations
    }
    final uniquePaths = libraryPaths.toSet().toList();
    return uniquePaths;
  }

  /// Scans Steam directories for installed Proton builds.
  Future<List<ProtonBuild>> _scanForSteamProtonBuilds() async {
    List<ProtonBuild> foundBuilds = [];
    final homeDir = Platform.environment['HOME'];
    if (homeDir == null) {
      // ERROR: HOME environment variable not set. Cannot scan for Steam Proton builds.
      return foundBuilds;
    }

    // Potential Steam installation roots
    final List<String> potentialSteamRoots = [
      p.join(homeDir, '.steam', 'steam'),
      p.join(homeDir, '.steam', 'root'),
      p.join(homeDir, '.local', 'share', 'Steam'),
      p.join(homeDir, '.var', 'app', 'com.valvesoftware.Steam', '.local', 'share', 'Steam'), // Flatpak
    ];

    Set<String> pathsToScanForCompatTools = {};

    // Find actual Steam roots and add their potential compat tools dirs
    for (final steamRoot in potentialSteamRoots) {
       final steamRootDir = Directory(steamRoot);
       if (await steamRootDir.exists()) {
          // Add the compat tools dir directly under the root
          pathsToScanForCompatTools.add(p.join(steamRoot, 'compatibilitytools.d'));

          // Also check libraries defined in VDF for their own compat tools dirs
          final libraryPaths = await _getSteamLibraryPaths(steamRoot);
          for (final libPath in libraryPaths) {
             // It's less common, but check if compat tools exist directly in library roots too
             pathsToScanForCompatTools.add(p.join(libPath, 'compatibilitytools.d'));
          }
       } else {
          // Potential Steam root not found
       }
    }

    if (pathsToScanForCompatTools.isEmpty) {
       // No potential compatibilitytools.d paths found.
       return foundBuilds;
    }


    for (final compatPath in pathsToScanForCompatTools) {
      final compatDir = Directory(compatPath);

      if (await compatDir.exists()) {
        try {
          await for (final entity in compatDir.list()) {
            // Proton builds are directories within compatibilitytools.d
            if (entity is Directory) {
              // final dirName = p.basename(entity.path); // Removed unused variable
              try {
                // Check for key files/dirs to confirm validity
                final protonScript = File(p.join(entity.path, 'proton'));
                final versionFile = File(p.join(entity.path, 'version'));
                final distDir = Directory(p.join(entity.path, 'dist')); // Official builds have 'dist'

                // Use existence of 'proton' script OR 'version' file OR 'dist' dir
                if (await protonScript.exists() || await versionFile.exists() || await distDir.exists()) {
                   if (!foundBuilds.any((b) => b.installPath == entity.path)) {
                      // FIX: Corrected call to only pass path
                      foundBuilds.add(ProtonBuild.fromInstallPath(entity.path));
                   } else {
                      // Skipping duplicate found build
                   }
                } else {
                   // Skipping: Missing key files/dirs
                }
              } catch (e) {
                // Error processing Proton directory
              }
            }
          }
        } catch (e) {
          // Error listing directory
        }
      } else {
         // Compatibility path does not exist
      }
    }

    // Found installed Steam Proton builds after scan.
    return foundBuilds;
  }

  Future<List<BaseBuild>> fetchBuilds(Settings? settings) async {
    if (settings == null) {
      throw Exception('Settings not initialized');
    }

    List<BaseBuild> builds = [];

    // --- Fetch Wine builds ---
    try {
      final wineResponse = await http.get(Uri.parse(settings.wineBuildsApiUrl));
      if (wineResponse.statusCode == 200) {
        final wineData = json.decode(wineResponse.body);
        final List<dynamic> wineAssets = (wineData is Map && wineData.containsKey('assets'))
            ? wineData['assets']
            : (wineData is List ? wineData : []);

        final List<Map<String, dynamic>> typedWineAssets = wineAssets
            .whereType<Map<String, dynamic>>()
            .where((asset) => asset['name']?.toString().endsWith('.tar.xz') == true)
            .toList();

        List<WineBuild> wineBuilds = [];
        for (var asset in typedWineAssets) {
           try {
              wineBuilds.add(WineBuild.fromGitHubAsset(asset, wineData['tag_name'] ?? 'unknown'));
           } catch (e) {
              // Error parsing Wine asset
           }
        }
        builds.addAll(wineBuilds);
        // Fetched Wine builds.
      } else {
        // Failed to fetch Wine builds
      }
    } catch (e) {
       // Error fetching Wine builds
    }

    // --- Fetch Kronek Proton builds ---
    try {
      // Use the kronekProtonApiUrl setting instead of hardcoded URL
      final kronekResponse = await http.get(Uri.parse(settings.kronekProtonApiUrl));
      
      if (kronekResponse.statusCode == 200) {
        final kronekData = json.decode(kronekResponse.body);
        final List<dynamic> assets = kronekData.containsKey('assets') 
            ? kronekData['assets'] 
            : [];
        
        List<ProtonBuild> kronekBuilds = [];
        for (var asset in assets) {
          try {
            if (asset is Map<String, dynamic> && 
                asset['name']?.toString().contains('wine-proton') == true &&
                asset['name']?.toString().endsWith('.tar.xz') == true) {
              // Create a Kronek Proton build with a more user-friendly name
              final assetName = asset['name']?.toString() ?? '';
              final displayName = assetName.replaceAll('wine-proton-', 'Kronek Proton ').replaceAll('.tar.xz', '');
              
              kronekBuilds.add(ProtonBuild(
                name: assetName, // Use original asset name for file operations
                displayName: displayName, // Use the display name for UI
                downloadUrl: asset['browser_download_url'],
                version: kronekData['tag_name'] ?? 'unknown',
                type: PrefixType.proton,
              ));
            }
          } catch (e) {
            // Error parsing Kronek Proton asset
          }
        }
        builds.addAll(kronekBuilds);
        // Fetched Kronek Proton builds
      }
    } catch (e) {
      // Error fetching Kronek Proton builds
    }

    // --- Fetch CachyOS Proton builds ---
    try {
      final cachyOSResponse = await http.get(Uri.parse(settings.cachyOSProtonApiUrl));
      if (cachyOSResponse.statusCode == 200) {
        final List<dynamic> releases = json.decode(cachyOSResponse.body);
        List<ProtonBuild> cachyOSBuilds = [];
        releases
            .whereType<Map<String, dynamic>>()
            .where((release) => release['tag_name'] != null)
            .take(2) // Limit to latest 2 CachyOS Proton builds
            .forEach((release) {
              try {
                // Look for .tar.xz assets in CachyOS releases
                final assets = release['assets'] as List;
                final tarballAsset = assets.firstWhere(
                  (asset) => asset is Map && asset['name']?.toString().endsWith('.tar.xz') == true,
                  orElse: () => null,
                );
                
                if (tarballAsset != null) {
                  final Map<String, dynamic> tarballAssetMap = Map<String, dynamic>.from(tarballAsset);
                  
                  cachyOSBuilds.add(ProtonBuild(
                    name: tarballAssetMap['name'] ?? 'Unknown CachyOS Proton Build',
                    displayName: 'CachyOS Proton ${release['tag_name']?.toString().replaceFirst('cachyos-', '')}',
                    downloadUrl: tarballAssetMap['browser_download_url'] ?? '',
                    version: release['tag_name'] ?? 'unknown',
                    type: PrefixType.proton,
                    architecture: 'win64',
                  ));
                }
              } catch (e) {
                // Error parsing CachyOS Proton release
              }
            });
        builds.addAll(cachyOSBuilds);
        // Fetched CachyOS Proton builds.
      } else {
        // Failed to fetch CachyOS Proton builds
      }
    } catch (e) {
       // Error fetching CachyOS Proton builds
    }

    // --- Fetch Proton-GE builds ---
    try {
      final protonResponse = await http.get(Uri.parse(settings.protonGeApiUrl));
      if (protonResponse.statusCode == 200) {
        final List<dynamic> releases = json.decode(protonResponse.body);
        List<ProtonBuild> protonBuilds = [];
        releases
            .whereType<Map<String, dynamic>>()
            .where((release) => release['tag_name'] != null)
            .take(2) // Limit fetched Proton-GE builds to only the latest 2
            .forEach((release) {
              try {
                // Pass PrefixType.proton, ProtonBuild might override based on content/name
                protonBuilds.add(ProtonBuild.fromGitHubRelease(release, PrefixType.proton));
              } catch (e) {
                // Error parsing Proton-GE release
              }
            });
        builds.addAll(protonBuilds);
        // Fetched Proton-GE builds.
      } else {
        // Failed to fetch Proton-GE builds
      }
    } catch (e) {
       // Error fetching Proton-GE builds
    }

    // --- Scan for installed Steam Proton builds ---
    try {
       List<ProtonBuild> installedProtonBuilds = await _scanForSteamProtonBuilds();
       builds.addAll(installedProtonBuilds);
    } catch (e) {
       // Error scanning for installed Steam Proton builds
    }

    // --- Filter out unwanted builds ---
    builds.removeWhere((build) {
      // Remove Proton Experimental type (enum value was removed, check type just in case)
      // if (build.type == PrefixType.protonExperimental) return true; // No longer needed
      // Remove builds containing "UMU" in the name (case-insensitive)
      if (build.name.toLowerCase().contains('umu')) return true;
      return false;
    });


    // Total builds available for selection after fetch and scan
    // Sort builds: Installed first, then by type, then by version descending
    builds.sort((a, b) {
      int installSort = (a.installPath != null ? 0 : 1).compareTo(b.installPath != null ? 0 : 1);
      if (installSort != 0) return installSort;

      int typeSort = a.type.index.compareTo(b.type.index);
      if (typeSort != 0) return typeSort;

      // Attempt a more robust version sort (basic numeric comparison)
      final RegExp versionRegex = RegExp(r'(\d+)\.(\d+)(?:[.-](\d+))?');
      final Match? aMatch = versionRegex.firstMatch(a.version);
      final Match? bMatch = versionRegex.firstMatch(b.version);

      if (aMatch != null && bMatch != null) {
        try {
          int aMajor = int.parse(aMatch.group(1)!);
          int bMajor = int.parse(bMatch.group(1)!);
          if (aMajor != bMajor) return bMajor.compareTo(aMajor); // Descending major

          int aMinor = int.parse(aMatch.group(2)!);
          int bMinor = int.parse(bMatch.group(2)!);
          if (aMinor != bMinor) return bMinor.compareTo(aMinor); // Descending minor

          int aPatch = int.tryParse(aMatch.group(3) ?? '0') ?? 0;
          int bPatch = int.tryParse(bMatch.group(3) ?? '0') ?? 0;
          if (aPatch != bPatch) return bPatch.compareTo(aPatch); // Descending patch
        } catch (_) {
           // Fallback to string compare if parsing fails
           return b.version.compareTo(a.version);
        }
      }
      // Fallback for non-matching version strings
      return b.version.compareTo(a.version);
    });

    // Filter to keep only the two latest Proton builds
    // First, separate builds by type
    final Map<PrefixType, List<BaseBuild>> buildsByType = {};
    for (final build in builds) {
      buildsByType.putIfAbsent(build.type, () => []).add(build);
    }
    
    // Then filter Proton builds to keep only the latest two versions from each source
    if (buildsByType.containsKey(PrefixType.proton)) {
      // Separate by source (GE vs Kronek vs CachyOS)
      List<BaseBuild> geProtonBuilds = [];
      List<BaseBuild> kronekProtonBuilds = [];
      List<BaseBuild> cachyOSProtonBuilds = [];
      List<BaseBuild> otherProtonBuilds = []; // For Steam Proton or other sources
      
      for (final build in buildsByType[PrefixType.proton]!) {
        if (build.name.contains('GE-Proton')) {
          geProtonBuilds.add(build);
        } else if (build.name.contains('Kronek Proton')) {
          kronekProtonBuilds.add(build);
        } else if (build.displayName?.contains('CachyOS Proton') == true || build.name.contains('cachyos')) {
          cachyOSProtonBuilds.add(build);
        } else {
          otherProtonBuilds.add(build);
        }
      }
      
      // Keep the latest two from each source
      final List<BaseBuild> filteredProtonBuilds = [
        ...geProtonBuilds.take(2),
        ...kronekProtonBuilds.take(2),
        ...cachyOSProtonBuilds.take(2),
        ...otherProtonBuilds, // Keep all installed Steam Proton builds
      ];
      
      buildsByType[PrefixType.proton] = filteredProtonBuilds;
    }
    
    // Rebuild the flattened list
    builds = buildsByType.values.expand((builds) => builds).toList();

    return builds;
  }
}