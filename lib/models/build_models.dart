import 'dart:io'; // Import dart:io for Platform
import 'prefix_models.dart';

abstract class BaseBuild {
  final String name;
  final String? displayName; // Added for UI display
  final String? downloadUrl; // Made optional
  final String version;
  final PrefixType type;
  final String? installPath; // Added for locally installed builds

  BaseBuild({
    required this.name,
    this.displayName, // Optional display name
    this.downloadUrl, // Optional
    required this.version,
    required this.type,
    this.installPath, // Optional
  });
  
  // Getter to return display name or name if display name is null
  String get getDisplayName => displayName ?? name;
}

class WineBuild extends BaseBuild {
  WineBuild({
    required super.name,
    super.displayName,
    required String downloadUrl, // Wine builds always have a download URL from API
    required super.version,
  }) : super(type: PrefixType.wine, downloadUrl: downloadUrl); // Pass URL to base

  factory WineBuild.fromGitHubAsset(Map<String, dynamic> asset, String version) {
    return WineBuild(
      name: asset['name'] ?? 'Unknown Wine Build',
      downloadUrl: asset['browser_download_url'] ?? '',
      version: version,
    );
  }
}

class ProtonBuild extends BaseBuild {
  ProtonBuild({
    required super.name,
    super.displayName,
    super.downloadUrl, // Can be null for installed Steam Proton
    required super.version,
    required PrefixType type, // Keep type for consistency, but it will be Proton for installed
    super.installPath, // Pass installPath to base
  }) : super(type: type);

  // Factory for downloadable Proton-GE builds
  factory ProtonBuild.fromGitHubRelease(Map<String, dynamic> release, PrefixType type) {
    final assets = release['assets'] as List;
    final tarballAsset = assets.firstWhere(
      (asset) => asset is Map && asset['name']?.toString().endsWith('.tar.gz') == true,
      orElse: () => throw Exception('No .tar.gz asset found in release ${release['tag_name']}'),
    );

    final Map<String, dynamic> tarballAssetMap = Map<String, dynamic>.from(tarballAsset);

    return ProtonBuild(
      name: tarballAssetMap['name'] ?? 'Unknown Proton Build',
      downloadUrl: tarballAssetMap['browser_download_url'] ?? '', // Has download URL
      version: release['tag_name'] ?? 'unknown',
      type: type, // Use the passed type (should be Proton)
      // installPath is null for downloaded builds
    );
  }

  // Factory for locally installed Steam Proton builds
  // Updated: Removed type detection logic, always assumes Proton
  factory ProtonBuild.fromInstallPath(String path) {
     final dirName = path.split(Platform.pathSeparator).last;
     // Basic version extraction (might need refinement)
     // Keep the version extraction logic
     final version = dirName.replaceFirst('Proton ', '').replaceFirst('Experimental', '').trim();
     // Removed type detection based on name
     // final type = dirName.contains('Experimental')
     //     ? PrefixType.protonExperimental // Removed reference
     //     : PrefixType.proton;

     return ProtonBuild(
        name: dirName,
        displayName: "$dirName (Installed)", // Indicate it's installed in display name
        version: version.isNotEmpty ? version : dirName, // Use dirName if version parsing fails
        type: PrefixType.proton, // Always assign Proton type for installed builds
        installPath: path, // Set the install path
        // downloadUrl is null
     );
  }
}
