import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:process_run/shell.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart'; // Import Settings model
import 'log_service.dart'; // Import LogService

/// Service for downloading and installing components like DXVK and VKD3D-Proton
/// and general dependencies using winetricks.
class WineComponentInstaller {
  // Removed static const URLs

  /// Fetches information about the latest DXVK release
  Future<Map<String, dynamic>> getLatestDxvkRelease(Settings settings) async { // Added settings parameter
    final response = await http.get(Uri.parse(settings.dxvkApiUrl)); // Use settings URL
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load DXVK release information from ${settings.dxvkApiUrl}'); // Updated exception
    }
  }

  /// Fetches information about the latest VKD3D-Proton release
  Future<Map<String, dynamic>> getLatestVkd3dRelease(Settings settings) async { // Added settings parameter
    final response = await http.get(Uri.parse(settings.vkd3dApiUrl)); // Use settings URL
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load VKD3D-Proton release information from ${settings.vkd3dApiUrl}'); // Updated exception
    }
  }

  /// Downloads the assets from a GitHub release
  Future<String> _downloadRelease(String downloadUrl, String targetDir) async {
    final tempDir = Directory.systemTemp.createTempSync('wine_component_');
    final fileName = path.basename(downloadUrl);
    final downloadPath = path.join(tempDir.path, fileName);

    final request = http.Request('GET', Uri.parse(downloadUrl));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      tempDir.deleteSync(recursive: true);
      throw Exception('Failed to download file from $downloadUrl');
    }

    final file = File(downloadPath);
    await response.stream.pipe(file.openWrite());

    return downloadPath;
  }

  /// Extracts a tar.gz file to a specific directory
  Future<void> _extractTarGz(String filePath, String targetDir) async {
    final bytes = File(filePath).readAsBytesSync();

    // Decompress the gz file
    final gzBytes = GZipDecoder().decodeBytes(bytes);

    // Extract the tar file contents
    final archive = TarDecoder().decodeBytes(gzBytes);

    // Create target directory if it doesn't exist
    Directory(targetDir).createSync(recursive: true);

    // Extract files
    for (final file in archive) {
      final outFile = File(path.join(targetDir, file.name));
      if (file.isFile) {
        outFile.createSync(recursive: true);
        outFile.writeAsBytesSync(file.content as List<int>);
      } else {
        Directory(path.join(targetDir, file.name)).createSync(recursive: true);
      }
    }
  }

  /// Installs DXVK to a Wine prefix
  Future<bool> installDxvk(WinePrefix prefix, Settings settings, {Function(String)? progressCallback}) async { // Added settings parameter
    // Allow installation for Wine and Gaming types. Proton types manage their own.
    // Removed check for protonExperimental
    if (prefix.type == PrefixType.proton) {
      progressCallback?.call('DXVK installation is not typically needed for Proton prefixes.');
      return true; // Consider it successful, as Proton handles it.
    }

    String? downloadPath;
    Directory? extractDir;
    String? dxvkVersionTag; // To store the version tag

    try {
      progressCallback?.call('Fetching latest DXVK release information...');
      final release = await getLatestDxvkRelease(settings); // Pass settings
      dxvkVersionTag = release['tag_name']?.toString(); // Store the tag name
      final assets = release['assets'] as List;

      // Log all assets to debug
      progressCallback?.call('Found ${assets.length} assets in the release');
      for (var asset in assets) {
        progressCallback?.call('Asset: ${asset['name']}');
      }

      // Find the correct asset - try different naming patterns
      Map<String, dynamic>? dxvkAsset;

      // Try different naming patterns
      for (var asset in assets) {
        final name = asset['name'].toString();
        if (name.startsWith('dxvk-') && name.endsWith('.tar.gz')) {
          dxvkAsset = asset;
          break;
        }
      }

      // If still not found, try less strict pattern
      if (dxvkAsset == null) {
        for (var asset in assets) {
          final name = asset['name'].toString().toLowerCase();
          if (name.contains('dxvk') && name.endsWith('.tar.gz')) {
            dxvkAsset = asset;
            break;
          }
        }
      }

      String dxvkDirToInstallFrom;

      if (dxvkAsset == null) {
        progressCallback?.call('Could not find DXVK tar.gz asset in the release. Trying direct download URL...');
        // Try a direct hardcoded URL as fallback
        if (dxvkVersionTag == null) {
          progressCallback?.call('Could not determine DXVK version tag.');
          return false;
        }
        final directUrl = 'https://github.com/doitsujin/dxvk/releases/download/$dxvkVersionTag/dxvk-$dxvkVersionTag.tar.gz';
        progressCallback?.call('Trying direct URL: $directUrl');

        downloadPath = await _downloadRelease(directUrl, prefix.path);
        progressCallback?.call('Downloaded DXVK successfully using direct URL');

        // Continue with extraction
        progressCallback?.call('Extracting DXVK...');
        extractDir = Directory.systemTemp.createTempSync('dxvk_extract_');
        await _extractTarGz(downloadPath, extractDir.path);

        // Find the extracted directory
        final contents = extractDir.listSync();
        progressCallback?.call('Extracted ${contents.length} items');

        Directory? dxvkDir;
        for (var item in contents) {
          if (item is Directory && path.basename(item.path).startsWith('dxvk')) {
            dxvkDir = item;
            break;
          }
        }

        if (dxvkDir == null) {
          progressCallback?.call('Could not find DXVK directory in the extracted files');
          return false;
        }
        dxvkDirToInstallFrom = dxvkDir.path;

      } else {
        // Regular asset download flow
        progressCallback?.call('Downloading DXVK ${dxvkVersionTag ?? 'unknown version'}...');
        final downloadUrl = dxvkAsset['browser_download_url'];
        downloadPath = await _downloadRelease(downloadUrl, prefix.path);

        // Continue with the original flow
        progressCallback?.call('Extracting DXVK...');
        extractDir = Directory.systemTemp.createTempSync('dxvk_extract_');
        await _extractTarGz(downloadPath, extractDir.path);

        // Find the extracted directory
        final dxvkDirs = extractDir.listSync()
          .whereType<Directory>()
          .where((dir) => path.basename(dir.path).startsWith('dxvk-'))
          .toList();

        if (dxvkDirs.isEmpty) {
          progressCallback?.call('Could not find DXVK directory in extracted archive. Looking for any directory...');
          final anyDirs = extractDir.listSync().whereType<Directory>().toList();
          if (anyDirs.isEmpty) {
            progressCallback?.call('No directories found in the extracted archive');
            return false;
          }
          dxvkDirToInstallFrom = anyDirs.first.path;
          progressCallback?.call('Using directory: ${path.basename(dxvkDirToInstallFrom)}');
        } else {
          dxvkDirToInstallFrom = dxvkDirs.first.path;
        }
      }

      // Install the DLLs
      progressCallback?.call('Installing DXVK DLLs to prefix...');
      final x64Dir = path.join(dxvkDirToInstallFrom, 'x64');
      final x32Dir = path.join(dxvkDirToInstallFrom, 'x32');

      // Ensure the Windows system directories exist
      final sys32Dir = Directory(path.join(prefix.path, 'drive_c', 'windows', 'system32'));
      final sysWow64Dir = Directory(path.join(prefix.path, 'drive_c', 'windows', 'syswow64'));
      sys32Dir.createSync(recursive: true);
      sysWow64Dir.createSync(recursive: true);

      // Copy the DLLs
      bool copied64 = false;
      if (Directory(x64Dir).existsSync()) {
        for (var file in Directory(x64Dir).listSync()) {
          if (file is File && path.extension(file.path) == '.dll') {
            final targetPath = path.join(sys32Dir.path, path.basename(file.path));
            file.copySync(targetPath);
            copied64 = true;
          }
        }
      }
      if (copied64) progressCallback?.call('Copied x64 DLLs.');

      bool copied32 = false;
      if (Directory(x32Dir).existsSync()) {
        for (var file in Directory(x32Dir).listSync()) {
          if (file is File && path.extension(file.path) == '.dll') {
            final targetPath = path.join(sysWow64Dir.path, path.basename(file.path));
            file.copySync(targetPath);
            copied32 = true;
          }
        }
      }
      if (copied32) progressCallback?.call('Copied x32 DLLs.');

      // Run winecfg after copying DLLs
      progressCallback?.call('Running winecfg to apply changes...');
      try {
        // Run asynchronously, don't wait for it to finish
        Process.start(
          'winecfg',
          [],
          environment: {'WINEPREFIX': prefix.path},
          runInShell: true // May help find winecfg in PATH
        );
        progressCallback?.call('winecfg launched. Check the Wine configuration window.');
      } catch (winecfgError) {
        progressCallback?.call('Failed to launch winecfg: $winecfgError. DXVK DLLs are copied, but you may need to run winecfg manually.');
        // Don't return false here, as DLLs were copied.
      }

      progressCallback?.call('DXVK ${dxvkVersionTag ?? 'unknown version'} DLLs installed successfully.');
      return true;

    } catch (e) {
      progressCallback?.call('Error installing DXVK: $e');
      return false;
    } finally {
      // Cleanup
      try {
        if (downloadPath != null && await File(downloadPath).exists()) {
          await File(downloadPath).delete();
        }
        if (extractDir != null && await extractDir.exists()) {
          await extractDir.delete(recursive: true);
        }
      } catch (cleanupError) {
        progressCallback?.call('Warning: Error during cleanup: $cleanupError');
      }
    }
  }

  /// Installs VKD3D-Proton to a Wine prefix
  Future<bool> installVkd3d(WinePrefix prefix, Settings settings, {Function(String)? progressCallback}) async {
    final logService = LogService(); // Get logger instance
    // Allow installation for Wine and Gaming types. Proton types manage their own.
    // Removed check for protonExperimental
    if (prefix.type == PrefixType.proton) {
      progressCallback?.call('VKD3D-Proton installation is not typically needed for Proton prefixes.');
      return true; // Consider it successful, as Proton handles it.
    }

    String? downloadPath;
    Directory? extractDir;

    try {
      // Use the specific version URL instead of fetching from GitHub API
      const specificVersion = 'v2.14.1';
      const specificVersionNumber = '2.14.1';
      const directUrl = 'https://github.com/HansKristian-Work/vkd3d-proton/releases/download/$specificVersion/vkd3d-proton-$specificVersionNumber.tar.zst';

      progressCallback?.call('Using VKD3D-Proton $specificVersionNumber');
      progressCallback?.call('Downloading from: $directUrl');

      try {
        downloadPath = await _downloadRelease(directUrl, prefix.path);
        final msg = 'Downloaded VKD3D-Proton successfully to $downloadPath';
        progressCallback?.call(msg);
        logService.log(msg);
      } catch (e) {
        progressCallback?.call('Download failed: $e');
        logService.log('VKD3D-Proton download failed: $e', LogLevel.error); return false;
      }

      // Extract the archive
      progressCallback?.call('Extracting VKD3D-Proton...');

      // Check file extension to determine extraction method
      extractDir = Directory.systemTemp.createTempSync('vkd3d_extract_');

      if (path.extension(downloadPath) == '.zst') {
        // Use external zstd command for .tar.zst files
        progressCallback?.call('Using zstd to extract .tar.zst file...');

        // First, check if zstd and tar are installed
        final zstdCheckResults = await Shell(verbose: false).run('which zstd'); // Corrected variable name
        final tarCheckResults = await Shell(verbose: false).run('which tar'); // Corrected variable name
        if (zstdCheckResults.first.exitCode != 0) { // Access first result
          progressCallback?.call('Error: zstd not found. Please install zstd to extract .tar.zst files.');
          logService.log('zstd command not found, cannot extract VKD3D.', LogLevel.error); return false;
        }
        if (tarCheckResults.first.exitCode != 0) { // Access first result
          progressCallback?.call('Error: tar not found. Please install tar to extract .tar.zst files.');
          logService.log('tar command not found, cannot extract VKD3D.', LogLevel.error); return false;
        }

        // Extract using zstd to get the tar file
        final tarFile = path.join(path.dirname(downloadPath), 'vkd3d-proton.tar');
        final zstdResult = await Process.run('zstd', ['-d', downloadPath, '-o', tarFile]);

        if (zstdResult.exitCode != 0) {
          progressCallback?.call('Error extracting with zstd: ${zstdResult.stderr}');
          logService.log('zstd extraction failed: ${zstdResult.stderr}', LogLevel.error); return false;
        }

        // Now extract the tar file
        final tarResult = await Process.run('tar', ['-xf', tarFile, '-C', extractDir.path]);

        if (tarResult.exitCode != 0) {
          progressCallback?.call('Error extracting tar: ${tarResult.stderr}');
          logService.log('tar extraction failed: ${tarResult.stderr}', LogLevel.error); return false;
        }

        // Clean up the intermediate tar file
        await File(tarFile).delete();
      } else {
        // Use the existing method for .tar.gz
        await _extractTarGz(downloadPath, extractDir.path);
      }

      // Look for the setup script
      progressCallback?.call('Looking for setup script...');
      File? setupScriptFile;

      void findSetupScript(Directory dir) {
        for (var entity in dir.listSync()) {
          if (entity is File && path.basename(entity.path) == 'setup_vkd3d_proton.sh') {
            setupScriptFile = entity;
            return;
          } else if (entity is Directory) {
            findSetupScript(entity);
          }
        }
      }

      findSetupScript(extractDir);

      if (setupScriptFile == null) {
        // If no script found, list contents for debugging
        progressCallback?.call('Could not find setup_vkd3d_proton.sh. Contents of extracted directory:');
        _listDirectoryContents(extractDir, progressCallback);
        logService.log('setup_vkd3d_proton.sh not found in extracted archive.', LogLevel.error); return false;
      }

      progressCallback?.call('Found setup script at: ${setupScriptFile!.path}');

      // Make setup script executable
      await Process.run('chmod', ['+x', setupScriptFile!.path]);

      // Run the setup script
      progressCallback?.call('Installing VKD3D-Proton to prefix: ${prefix.path}');
      final result = await Process.run(
        'bash', // Explicitly use bash
        [setupScriptFile!.path, 'install'], // Pass script path and 'install' arg
        environment: {'WINEPREFIX': prefix.path},
        workingDirectory: path.dirname(setupScriptFile!.path),
        stdoutEncoding: utf8, // Capture output as UTF8
        stderrEncoding: utf8,
      );

      // Log script output regardless of exit code
      logService.log('VKD3D Setup Script STDOUT:\n${result.stdout}');
      logService.log('VKD3D Setup Script STDERR:\n${result.stderr}');

      if (result.exitCode != 0) {
        progressCallback?.call('VKD3D-Proton installation failed (Exit Code: ${result.exitCode}): ${result.stderr}');
        logService.log('VKD3D setup script failed (Exit Code: ${result.exitCode})', LogLevel.error); return false;
      }

      final successMsg = 'VKD3D-Proton $specificVersionNumber has been installed successfully';
      progressCallback?.call(successMsg);
      logService.log(successMsg);
      return true;
    } catch (e) {
      progressCallback?.call('Error installing VKD3D-Proton: $e');
      logService.log('Exception during VKD3D-Proton installation: $e', LogLevel.error); return false;
    } finally {
      // Cleanup
      try {
        if (downloadPath != null && await File(downloadPath).exists()) {
          await File(downloadPath).delete();
        }
        if (extractDir != null && await extractDir.exists()) {
          await extractDir.delete(recursive: true);
        }
      } catch (cleanupError) {
        progressCallback?.call('Warning: Error during cleanup: $cleanupError');
        logService.log('Warning: Error during VKD3D cleanup: $cleanupError', LogLevel.warning);
      }
    }
  }

  // Helper method to list directory contents recursively for debugging
  void _listDirectoryContents(Directory dir, Function(String)? progressCallback, {String indent = ''}) {
    try {
      for (var entity in dir.listSync()) {
        if (entity is File) {
          progressCallback?.call('$indent${path.basename(entity.path)}');
        } else if (entity is Directory) {
          progressCallback?.call('$indent${path.basename(entity.path)}/');
          _listDirectoryContents(entity, progressCallback, indent: '$indent  ');
        }
      }
    } catch (e) {
      progressCallback?.call('$indent[Error listing contents: $e]');
    }
  }

  /// Installs a component (verb) using winetricks into the specified prefix.
  Future<void> installComponent({
    required String prefixPath,
    required String component,
    required String wineExecutablePath, // Path to the 'wine' binary (e.g., 'wine' or '/path/to/build/bin/wine')
    required Function(String status) onStatusUpdate,
  }) async {
    final logService = LogService();
    logService.log('Attempting to install component "$component" into prefix "$prefixPath" using wine at "$wineExecutablePath"');

    // Check if winetricks is installed
    final winetricksCheckResults = await Shell(verbose: false).run('which winetricks');
    final winetricksCheck = winetricksCheckResults.first; // Get the first result
    if (winetricksCheck.exitCode != 0) {
      final errorMsg = 'Error: winetricks command not found. Please install winetricks.';
      logService.log(errorMsg, LogLevel.error);
      onStatusUpdate(errorMsg);
      throw Exception(errorMsg);
    }

    final shell = Shell(
      environment: {
        'WINEPREFIX': prefixPath,
        'WINE': wineExecutablePath, // Tell winetricks which wine binary to use
      },
      verbose: false, // Keep shell output minimal unless debugging
    );

    onStatusUpdate('Running winetricks $component...');
    logService.log('Executing: WINEPREFIX="$prefixPath" WINE="$wineExecutablePath" winetricks -q $component');

    try {
      // Use -q for quiet mode to reduce unnecessary dialogs
      final results = await shell.run('winetricks -q $component');
      final result = results.first; // Get the first result

      if (result.exitCode != 0) {
        final errorMsg = 'Winetricks failed for component "$component" (Exit Code: ${result.exitCode}): ${result.stderr}';
        logService.log(errorMsg, LogLevel.error);
        onStatusUpdate('Error installing $component: ${result.stderr.isNotEmpty ? result.stderr : result.stdout}'); // Show stdout if stderr is empty
        throw Exception(errorMsg);
      }

      onStatusUpdate('Component "$component" installed successfully.');
      logService.log('Component "$component" installed successfully.');
    } catch (e) {
      final errorMsg = 'Error running winetricks for component "$component": $e';
      logService.log(errorMsg, LogLevel.error);
      onStatusUpdate('Error installing $component: $e');
      rethrow; // Re-throw the exception to be handled by the caller
    }
  }
}
