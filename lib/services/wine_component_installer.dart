import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:process_run/shell.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart'; // Import Settings model
import 'log_service.dart'; // Import LogService
import 'package:dio/dio.dart';

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

  /// Extracts a tar.zst file to a specific directory
  Future<void> _extractTarZst(String filePath, String targetDir) async {
    final bytes = File(filePath).readAsBytesSync();

    // Decompress the zst file
    // Note: Dart's 'archive' package doesn't support Zstandard directly.
    // We'll use the system's `tar` command for this as a workaround.
    // This requires `zstd` to be installed on the system.
    Directory(targetDir).createSync(recursive: true);
    final shell = Shell(verbose: false); // Use a local shell instance
    try {
      await shell.run('tar -xf "$filePath" -C "$targetDir" --use-compress-program=unzstd');
    } catch (e) {
      // Fallback if unzstd is not available or tar doesn't support it directly
      LogService().log('tar with unzstd failed: $e. Trying zstd -d and then tar -xf.', LogLevel.warning);
      final tempTarPath = '${filePath}.tar';
      await shell.run('zstd -d "$filePath" -o "$tempTarPath"');
      await shell.run('tar -xf "$tempTarPath" -C "$targetDir"');
      await File(tempTarPath).delete(); // Clean up temporary .tar file
    }
  }

  /// Installs DXVK to a Wine prefix
  Future<bool> installDxvk(WinePrefix prefix, Settings settings, {Function(String)? progressCallback, String? customWineExecutable, Map<String, String>? customEnv}) async { // Added settings, customWineExecutable, customEnv
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
      progressCallback?.call('Installing DXVK DLLs to prefix (${prefix.architecture})...');
      final x64Dir = path.join(dxvkDirToInstallFrom, 'x64');
      final x32Dir = path.join(dxvkDirToInstallFrom, 'x32');

      // Ensure the Windows system directories exist
      final sys32Dir = Directory(path.join(prefix.path, 'drive_c', 'windows', 'system32'));
      sys32Dir.createSync(recursive: true);

      bool copiedDlls = false;

      if (prefix.architecture == 'win64') {
        // For 64-bit prefixes, x64 DLLs go to system32, and x32 DLLs go to syswow64
        final sysWow64Dir = Directory(path.join(prefix.path, 'drive_c', 'windows', 'syswow64'));
        sysWow64Dir.createSync(recursive: true);

        if (Directory(x64Dir).existsSync()) {
          for (var file in Directory(x64Dir).listSync()) {
            if (file is File && path.extension(file.path) == '.dll') {
              final targetPath = path.join(sys32Dir.path, path.basename(file.path));
              file.copySync(targetPath);
              copiedDlls = true;
            }
          }
        }
        if (copiedDlls) progressCallback?.call('Copied x64 DLLs to system32.');
        
        bool copied32ToSyswow64 = false;
        if (Directory(x32Dir).existsSync()) {
          for (var file in Directory(x32Dir).listSync()) {
            if (file is File && path.extension(file.path) == '.dll') {
              final targetPath = path.join(sysWow64Dir.path, path.basename(file.path));
              file.copySync(targetPath);
              copied32ToSyswow64 = true;
            }
          }
        }
        if (copied32ToSyswow64) progressCallback?.call('Copied x32 DLLs to syswow64.');
        copiedDlls = copiedDlls || copied32ToSyswow64;

      } else { // win32 architecture
        // For 32-bit prefixes, x32 DLLs go to system32. x64 DLLs are not used.
        if (Directory(x32Dir).existsSync()) {
          for (var file in Directory(x32Dir).listSync()) {
            if (file is File && path.extension(file.path) == '.dll') {
              final targetPath = path.join(sys32Dir.path, path.basename(file.path));
              file.copySync(targetPath);
              copiedDlls = true;
            }
          }
        }
        if (copiedDlls) progressCallback?.call('Copied x32 DLLs to system32.');
      }

      // Run winecfg after copying DLLs
      if (copiedDlls) { // Only run winecfg if DLLs were actually copied
        progressCallback?.call('Running winecfg to apply changes...');
        try {
          // Run asynchronously, don't wait for it to finish
          Process.start(
            customWineExecutable ?? 'winecfg', // Use custom wine executable if provided
            [],
            environment: customEnv ?? {'WINEPREFIX': prefix.path}, // Use custom env if provided
            runInShell: true // May help find winecfg in PATH
          );
          progressCallback?.call('winecfg launched. Check the Wine configuration window.');
        } catch (winecfgError) {
          progressCallback?.call('Failed to launch winecfg: $winecfgError. DXVK DLLs are copied, but you may need to run winecfg manually.');
          // Don't return false here, as DLLs were copied.
        }
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
  Future<bool> installVkd3d(WinePrefix prefix, Settings settings, {Function(String)? progressCallback, String? customWineExecutable, Map<String, String>? customEnv}) async {
    // Allow installation for Wine and Gaming types. Proton types manage their own.
    if (prefix.type == PrefixType.proton) {
      progressCallback?.call('VKD3D-Proton installation is not typically needed for Proton prefixes.');
      return true; // Consider it successful, as Proton handles it.
    }

    String? downloadPath;
    Directory? tempDownloadDir;
    Directory? extractDir;
    String? vkd3dVersionTag;
    final LogService logService = LogService(); // Use a local instance or pass it if preferred

    try {
      progressCallback?.call('Fetching latest VKD3D-Proton release information...');
      logService.log('Fetching latest VKD3D-Proton release from ${settings.vkd3dApiUrl}');
      final release = await getLatestVkd3dRelease(settings);
      vkd3dVersionTag = release['tag_name']?.toString();
      final assets = release['assets'] as List;
      progressCallback?.call('Found ${assets.length} assets in VKD3D-Proton release ${vkd3dVersionTag ?? ""}');

      final vkd3dAsset = assets.firstWhere(
        (asset) => asset['name'].toString().endsWith('.tar.zst'),
        orElse: () => null,
      );

      if (vkd3dAsset == null) {
        progressCallback?.call('Could not find VKD3D-Proton .tar.zst asset.');
        logService.log('VKD3D-Proton .tar.zst asset not found in release: ${release['html_url']}', LogLevel.error);
        return false;
      }

      final downloadUrl = vkd3dAsset['browser_download_url'];
      final fileName = vkd3dAsset['name'];
      logService.log('Found VKD3D asset: $fileName');
      progressCallback?.call('Downloading VKD3D-Proton ${vkd3dVersionTag ?? fileName}...');
      
      tempDownloadDir = await Directory.systemTemp.createTemp('vkd3d_download_');
      downloadPath = path.join(tempDownloadDir.path, fileName);

      final dio = Dio();
      await dio.download(downloadUrl, downloadPath, onReceiveProgress: (received, total) {
        if (total > 0) {
          final progress = (received / total * 100).toStringAsFixed(1);
          progressCallback?.call('Downloading VKD3D: $progress%');
        }
      });
      logService.log('VKD3D-Proton downloaded to $downloadPath');

      progressCallback?.call('Extracting VKD3D-Proton...');
      extractDir = await Directory.systemTemp.createTemp('vkd3d_extract_');
      await _extractTarZst(downloadPath, extractDir.path);
      logService.log('VKD3D-Proton extracted to ${extractDir.path}');

      // The actual DLLs are usually inside a versioned subdirectory
      final extractedItems = extractDir.listSync();
      Directory? vkd3dInstallDir;
      
      List<Directory> potentialDirs = extractedItems.whereType<Directory>().toList();
      if (potentialDirs.isNotEmpty) {
        vkd3dInstallDir = potentialDirs.firstWhere(
          (dir) => path.basename(dir.path).startsWith('vkd3d-proton'),
          // If no specific 'vkd3d-proton*' directory is found, try to use the first directory found.
          orElse: () => potentialDirs.first, 
        );
      }

      if (vkd3dInstallDir == null || !await vkd3dInstallDir.exists()) {
          logService.log('Could not find the main VKD3D directory (e.g., vkd3d-proton-X.Y) in ${extractDir.path}. Extracted items: ${extractedItems.map((e) => e.path).join(', ')}', LogLevel.error);
          progressCallback?.call('Error: Could not locate VKD3D files after extraction.');
          return false;
      }
      logService.log('Using VKD3D installation directory: ${vkd3dInstallDir.path}');


      final String vkd3dDllSourceDir64 = path.join(vkd3dInstallDir.path, 'x64');
      final String vkd3dDllSourceDir32 = path.join(vkd3dInstallDir.path, 'x86');

      final String system32TargetDir = path.join(prefix.path, 'drive_c', 'windows', 'system32');
      final String syswow64TargetDir = path.join(prefix.path, 'drive_c', 'windows', 'syswow64');

      await Directory(system32TargetDir).create(recursive: true);
      await Directory(syswow64TargetDir).create(recursive: true);

      final List<String> dllsToCopy = ['d3d12.dll', 'd3d12core.dll'];
      bool copiedAnyDlls = false;

      if (prefix.architecture == 'win64') {
        logService.log('Copying 64-bit VKD3D DLLs to $system32TargetDir for win64 prefix...');
        progressCallback?.call('Copying 64-bit VKD3D DLLs to system32...');
        for (final dll in dllsToCopy) {
          final sourceFile = path.join(vkd3dDllSourceDir64, dll);
          final destinationFile = path.join(system32TargetDir, dll);
          if (await File(sourceFile).exists()) {
            await _copyFileWithBackup(sourceFile, destinationFile, logService);
            logService.log('Copied $sourceFile to $destinationFile');
            copiedAnyDlls = true;
          } else {
            logService.log('Source DLL not found: $sourceFile for win64 system32', LogLevel.warning);
          }
        }

        logService.log('Copying 32-bit VKD3D DLLs to $syswow64TargetDir for win64 prefix...');
        progressCallback?.call('Copying 32-bit VKD3D DLLs to syswow64...');
        for (final dll in dllsToCopy) {
          final sourceFile = path.join(vkd3dDllSourceDir32, dll);
          final destinationFile = path.join(syswow64TargetDir, dll);
           if (await File(sourceFile).exists()) {
            await _copyFileWithBackup(sourceFile, destinationFile, logService);
            logService.log('Copied $sourceFile to $destinationFile');
            copiedAnyDlls = true;
          } else {
            logService.log('Source DLL not found: $sourceFile for win64 syswow64', LogLevel.warning);
          }
        }
      } else { // win32
        logService.log('Copying 32-bit VKD3D DLLs to $system32TargetDir for win32 prefix...');
        progressCallback?.call('Copying 32-bit VKD3D DLLs to system32...');
        for (final dll in dllsToCopy) {
          final sourceFile = path.join(vkd3dDllSourceDir32, dll);
          final destinationFile = path.join(system32TargetDir, dll);
          if (await File(sourceFile).exists()) {
            await _copyFileWithBackup(sourceFile, destinationFile, logService);
            logService.log('Copied $sourceFile to $destinationFile');
            copiedAnyDlls = true;
          } else {
            logService.log('Source DLL not found: $sourceFile for win32 system32', LogLevel.warning);
          }
        }
      }

      if (!copiedAnyDlls) {
        final errorMessage = 'VKD3D-Proton: No DLLs were copied. Check source paths ($vkd3dDllSourceDir64, $vkd3dDllSourceDir32) and DLL names.';
        logService.log(errorMessage, LogLevel.error);
        progressCallback?.call('Error: $errorMessage');
        return false;
      }
      
      final successMessage = 'VKD3D-Proton ${vkd3dVersionTag ??fileName} installed successfully to prefix: ${prefix.path}';
      logService.log(successMessage);
      progressCallback?.call(successMessage);
      return true;

    } catch (e, s) {
      progressCallback?.call('Error installing VKD3D-Proton: $e');
      logService.log('Error installing VKD3D-Proton: $e\n$s', LogLevel.error);
      return false;
    } finally {
      // Clean up
      try {
        if (downloadPath != null && await File(downloadPath).exists()) {
          await File(downloadPath).delete();
        }
        if (tempDownloadDir != null && await tempDownloadDir.exists()) {
          await tempDownloadDir.delete(recursive: true);
        }
        if (extractDir != null && await extractDir.exists()) {
          await extractDir.delete(recursive: true);
        }
      } catch (e) {
        logService.log('Error cleaning up VKD3D temp files: $e', LogLevel.warning);
      }
    }
  }

  /// Installs a component (verb) using winetricks into the specified prefix.
  /// 
  /// The `component` parameter is the name of the Winetricks verb to install (e.g., 'dxvk', 'vcrun2019').
  /// The `prefix` parameter is the WinePrefix object representing the target prefix.
  /// The `progressCallback` is an optional function to receive status updates.
  /// The `customWineExecutable` is an optional path to a specific wine executable (e.g., for Proton).
  /// The `customEnv` is an optional map of environment variables for the Winetricks command.
  Future<void> installComponent(WinePrefix prefix, String component, {Function(String)? progressCallback, String? customWineExecutable, Map<String, String>? customEnv}) async {
    progressCallback?.call('Installing $component using Winetricks...');
    final logService = LogService();

    // Determine the environment for Winetricks
    // Start with Platform.environment, then merge customEnv, then specific overrides.
    final Map<String, String> winetricksEnv = {
      ...(Platform.environment),
      ...(customEnv ?? {}), // customEnv can override Platform.environment
      'WINEPREFIX': prefix.path, // Explicitly set WINEPREFIX
      'WINEARCH': prefix.architecture, // Explicitly set WINEARCH
    };

    // If customWineExecutable is provided, use it to set WINE and adjust PATH
    if (customWineExecutable != null && customWineExecutable.isNotEmpty) {
      winetricksEnv['WINE'] = customWineExecutable; // Explicitly set WINE
      final wineDir = path.dirname(customWineExecutable);
      // Prepend wineDir to PATH, ensuring existing PATH (from customEnv or Platform.env) is respected
      winetricksEnv['PATH'] = '$wineDir:${winetricksEnv['PATH'] ?? Platform.environment['PATH'] ?? ''}';
      logService.log('Using customWineExecutable for Winetricks: $customWineExecutable. PATH updated: ${winetricksEnv['PATH']}');
    } else if (customEnv?.containsKey('WINE') == true) {
      logService.log('Using WINE from customEnv for Winetricks: ${customEnv!['WINE']}');
    } else {
      logService.log('Using system WINE for Winetricks (customWineExecutable not provided and WINE not in customEnv).');
    }

    // Construct the command
    String command = 'winetricks -q $component';

    final shell = Shell(environment: winetricksEnv, verbose: true);

    try {
      logService.log(
        'Running Winetricks command: "$command" with env:\n'
        '  WINEPREFIX=${winetricksEnv['WINEPREFIX']}\n'
        '  WINEARCH=${winetricksEnv['WINEARCH']}\n'
        '  WINE=${winetricksEnv['WINE']}\n'
        '  PATH=${winetricksEnv['PATH']}'
      );
      final results = await shell.run(command);
      final result = results.first; // Assuming single command, take the first result

      if (result.exitCode == 0) {
        progressCallback?.call('$component installed successfully.');
        logService.log('Winetricks $component installed successfully. Output: ${result.outText}');
      } else {
        progressCallback?.call('Failed to install $component. Exit code: ${result.exitCode}');
        logService.log(
          'Winetricks $component installation failed. Exit code: ${result.exitCode}\nStdout: ${result.outText}\nStderr: ${result.errText}',
          LogLevel.error,
        );
        // Potentially throw an exception here if installation is critical
      }
    } catch (e, stackTrace) {
      progressCallback?.call('Error installing $component with Winetricks: $e');
      logService.log('Exception during Winetricks $component installation: $e\n$stackTrace', LogLevel.error);
      // Potentially throw an exception here
    }
  }
}

// Typedef for the status callback function
typedef StatusCallback = void Function(String status);

// Helper function to copy file with backup
// This can be a private method in the class or a top-level private function
// For now, adding as a private method to WineComponentInstaller
extension WineComponentInstallerHelpers on WineComponentInstaller {
  Future<void> _copyFileWithBackup(String sourcePath, String destinationPath, LogService logService) async {
    final destinationFile = File(destinationPath);
    final sourceFile = File(sourcePath);

    if (!await sourceFile.exists()) {
      logService.log('Source file for copy does not exist: $sourcePath', LogLevel.warning);
      return;
    }

    if (await destinationFile.exists()) {
      String backupPath = '$destinationPath.old';
      // If .old exists, try .old.bak, then .old.bak2 etc. (simple increment for now)
      int i = 0;
      while(await File(backupPath).exists()) {
        i++;
        backupPath = '$destinationPath.old$i';
      }
      try {
        await destinationFile.rename(backupPath);
        logService.log('Backed up existing file: $destinationPath to $backupPath');
      } catch (e) {
        logService.log('Failed to backup $destinationPath to $backupPath: $e', LogLevel.error);
        // Decide if this is fatal. For now, we'll try to overwrite if backup fails.
        try {
          await destinationFile.delete();
          logService.log('Deleted $destinationPath after failed backup to allow overwrite.');
        } catch (delErr) {
          logService.log('Failed to delete $destinationPath after failed backup: $delErr. Copy might fail.', LogLevel.error);
          return; // Cannot proceed if backup fails and delete fails
        }
      }
    }
    try {
      await sourceFile.copy(destinationPath);
      logService.log('Copied $sourcePath to $destinationPath');
    } catch (e) {
      logService.log('Failed to copy $sourcePath to $destinationPath: $e', LogLevel.error);
    }
  }
}
