import 'prefix_models.dart';

abstract class BaseBuild {
  final String name;
  final String downloadUrl;
  final String version;
  final PrefixType type;

  BaseBuild({
    required this.name,
    required this.downloadUrl,
    required this.version,
    required this.type,
  });
}

class WineBuild extends BaseBuild {
  WineBuild({
    required super.name,
    required super.downloadUrl,
    required super.version,
  }) : super(type: PrefixType.wine);

  factory WineBuild.fromGitHubAsset(Map<String, dynamic> asset, String version) {
    return WineBuild(
      name: asset['name'],
      downloadUrl: asset['browser_download_url'],
      version: version,
    );
  }
}

class ProtonBuild extends BaseBuild {
  ProtonBuild({
    required super.name,
    required super.downloadUrl,
    required super.version,
  }) : super(type: PrefixType.proton);

  factory ProtonBuild.fromGitHubRelease(Map<String, dynamic> release) {
    final assets = release['assets'] as List;
    final tarballAsset = assets.firstWhere(
      (asset) => asset['name'].toString().endsWith('.tar.gz'),
      orElse: () => throw Exception('No tarball found in release'),
    );

    return ProtonBuild(
      name: tarballAsset['name'],
      downloadUrl: tarballAsset['browser_download_url'],
      version: release['tag_name'],
    );
  }
}
