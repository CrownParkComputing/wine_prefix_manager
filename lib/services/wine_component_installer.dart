import 'dart:async';
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
      final tempTarPath = '$filePath.tar';
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

  /// Installs Microsoft Visual C++ Redistributable x64 (2015-2022) to a Wine prefix
  Future<bool> installVcRedistX64(WinePrefix prefix, Settings settings, {Function(String)? progressCallback, String? customWineExecutable, Map<String, String>? customEnv}) async {
    final logService = LogService();
    const vcRedistUrl = 'https://aka.ms/vs/17/release/vc_redist.x64.exe';
    Directory? tempDirForVcRedist;
    
    try {
      progressCallback?.call('Downloading Microsoft Visual C++ Redistributable (x64)...');
      logService.log('Starting VC++ Redistributable (x64) installation for prefix: ${prefix.path}');
      
      tempDirForVcRedist = await Directory.systemTemp.createTemp('vcredist_x64_');
      final vcRedistPath = path.join(tempDirForVcRedist.path, 'vc_redist.x64.exe');
      
      final dio = Dio();
      await dio.download(vcRedistUrl, vcRedistPath, onReceiveProgress: (received, total) {
        if (total > 0) {
          final progressPercent = (received / total * 100).toStringAsFixed(1);
          progressCallback?.call('Downloading VC++ Redist (x64): $progressPercent%');
        }
      });
      
      logService.log('VC++ Redistributable (x64) downloaded to $vcRedistPath');
      
      // Prepare environment for installation
      final installEnv = {
        ...(Platform.environment),
        ...(customEnv ?? {}),
        'WINEPREFIX': prefix.path,
        'WINEARCH': prefix.architecture,
      };
      
      if (customWineExecutable != null && customWineExecutable.isNotEmpty) {
        installEnv['WINE'] = customWineExecutable;
        final wineDir = path.dirname(customWineExecutable);
        installEnv['PATH'] = '$wineDir:${installEnv['PATH'] ?? Platform.environment['PATH'] ?? ''}';
      }
      
      final shell = Shell(environment: installEnv, verbose: true);
      
      progressCallback?.call('Installing VC++ Redistributable (x64)...');
      logService.log('Installing VC++ Redistributable (x64) with command: wine "$vcRedistPath" /install /passive /norestart');
      
      final wineExecutable = customWineExecutable ?? 'wine';
      bool installSuccess = false;
      
      // Check if this is a Proton wine executable that needs 'run' prefix
      final isProtonExecutable = customWineExecutable != null && 
          (customWineExecutable.contains('proton') || customWineExecutable.endsWith('/wine'));
      
      // Try multiple installation methods for better compatibility
      // Method 1: /install /passive /norestart
      List<String> vcInstallArgs;
      if (isProtonExecutable && !customWineExecutable!.endsWith('/wine')) {
        // For true Proton scripts, use 'run' prefix
        vcInstallArgs = ['run', vcRedistPath, '/install', '/passive', '/norestart'];
      } else {
        // For Wine executables or system wine, run directly
        vcInstallArgs = [vcRedistPath, '/install', '/passive', '/norestart'];
      }
      
      final vcInstallResult = await shell.runExecutableArguments(wineExecutable, vcInstallArgs);
      
      if (vcInstallResult.exitCode == 0 || vcInstallResult.exitCode == 3010) {
        installSuccess = true;
        logService.log('VC++ Redistributable (x64) installed successfully with /passive flag');
      } else {
        // Method 2: /quiet /norestart
        progressCallback?.call('Trying alternative installation method...');
        logService.log('Trying /quiet installation method for VC++ x64');
        
        List<String> vcInstallArgs2;
        if (isProtonExecutable && !customWineExecutable!.endsWith('/wine')) {
          vcInstallArgs2 = ['run', vcRedistPath, '/quiet', '/norestart'];
        } else {
          vcInstallArgs2 = [vcRedistPath, '/quiet', '/norestart'];
        }
        
        final vcInstallResult2 = await shell.runExecutableArguments(wineExecutable, vcInstallArgs2);
        
        if (vcInstallResult2.exitCode == 0 || vcInstallResult2.exitCode == 3010) {
          installSuccess = true;
          logService.log('VC++ Redistributable (x64) installed successfully with /quiet flag');
        } else {
          // Method 3: GUI mode
          progressCallback?.call('Trying interactive installation...');
          logService.log('Trying GUI installation mode for VC++ x64');
          
          List<String> vcInstallArgs3;
          if (isProtonExecutable && !customWineExecutable!.endsWith('/wine')) {
            vcInstallArgs3 = ['run', vcRedistPath];
          } else {
            vcInstallArgs3 = [vcRedistPath];
          }
          
          final vcInstallResult3 = await shell.runExecutableArguments(wineExecutable, vcInstallArgs3);
          
          if (vcInstallResult3.exitCode == 0 || vcInstallResult3.exitCode == 3010) {
            installSuccess = true;
            logService.log('VC++ Redistributable (x64) installed successfully in GUI mode');
          }
        }
      }
      
      if (installSuccess) {
        // Create registry entries for better compatibility
        await _createVcRedistRegistryEntries(prefix, wineExecutable, progressCallback);
        progressCallback?.call('VC++ Redistributable (x64) installed successfully.');
        return true;
      } else {
        final errorMsg = 'VC++ Redistributable (x64) installation failed with all methods. Last exit code: ${vcInstallResult.exitCode}\nStdErr: ${vcInstallResult.errText}';
        logService.log(errorMsg, LogLevel.error);
        progressCallback?.call('Error: VC++ Redistributable (x64) installation failed.');
        return false;
      }
      
    } catch (e, stackTrace) {
      final errorMsg = 'Error downloading or installing VC++ Redistributable (x64): $e';
      logService.log('$errorMsg\n$stackTrace', LogLevel.error);
      progressCallback?.call(errorMsg);
      return false;
    } finally {
      // Clean up temporary directory
      try {
        if (tempDirForVcRedist != null && await tempDirForVcRedist.exists()) {
          await tempDirForVcRedist.delete(recursive: true);
        }
      } catch (e) {
        logService.log('Error cleaning up VC++ Redist temp files: $e', LogLevel.warning);
      }
    }
  }

  /// Verifies VC++ redistributable installation by checking registry entries
  Future<bool> _verifyVcRedistInstallation(WinePrefix prefix, String customWineExecutable, Function(String)? progressCallback) async {
    final logService = LogService();
    
    try {
      progressCallback?.call('Verifying VC++ installation...');
      
      final installEnv = {
        ...Platform.environment,
        'WINEPREFIX': prefix.path,
        'WINEARCH': prefix.architecture,
      };
      
      if (customWineExecutable.isNotEmpty) {
        installEnv['WINE'] = customWineExecutable;
        final wineDir = path.dirname(customWineExecutable);
        installEnv['PATH'] = '$wineDir:${installEnv['PATH'] ?? Platform.environment['PATH'] ?? ''}';
      }
      
      final shell = Shell(environment: installEnv, verbose: true);
      
      // Check for VC++ registry entries using Wine's reg command
      final wineExecutable = customWineExecutable.isNotEmpty ? customWineExecutable : 'wine';
      
      // Check if this is a Proton wine executable that needs 'run' prefix
      final isProtonExecutable = customWineExecutable.isNotEmpty && 
          (customWineExecutable.contains('proton') || customWineExecutable.endsWith('/wine'));
      
      List<String> regArgs;
      if (isProtonExecutable && !customWineExecutable.endsWith('/wine')) {
        regArgs = ['run', 'reg', 'query', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64'];
      } else {
        regArgs = ['reg', 'query', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64'];
      }
      
      final regCheckResult = await shell.runExecutableArguments(wineExecutable, regArgs);
      
      if (regCheckResult.exitCode == 0) {
        logService.log('VC++ registry entries found');
        return true;
      }
      
      logService.log('VC++ registry verification failed or incomplete', LogLevel.warning);
      return false;
      
    } catch (e) {
      logService.log('Error verifying VC++ installation: $e', LogLevel.warning);
      return false;
    }
  }
  
  /// Manually creates VC++ registry entries for better game compatibility
  Future<bool> _createVcRedistRegistryEntries(WinePrefix prefix, String customWineExecutable, Function(String)? progressCallback) async {
    final logService = LogService();
    
    try {
      progressCallback?.call('Creating VC++ registry entries...');
      
      final installEnv = {
        ...Platform.environment,
        'WINEPREFIX': prefix.path,
        'WINEARCH': prefix.architecture,
      };
      
      if (customWineExecutable.isNotEmpty) {
        installEnv['WINE'] = customWineExecutable;
        final wineDir = path.dirname(customWineExecutable);
        installEnv['PATH'] = '$wineDir:${installEnv['PATH'] ?? Platform.environment['PATH'] ?? ''}';
      }
      
      final shell = Shell(environment: installEnv, verbose: true);
      
      // Check if this is a Proton wine executable that needs 'run' prefix
      final isProtonExecutable = customWineExecutable.isNotEmpty && 
          (customWineExecutable.contains('proton') || customWineExecutable.endsWith('/wine'));
      
      // Create essential VC++ registry entries that games commonly check using Wine's reg command
      final baseRegEntries = [
        // VC++ 2015-2022 x64
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64', '/v', 'Version', '/t', 'REG_SZ', '/d', '14.42.34433', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64', '/v', 'Major', '/t', 'REG_DWORD', '/d', '14', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64', '/v', 'Minor', '/t', 'REG_DWORD', '/d', '42', '/f'],
        // VC++ 2015-2022 x86
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86', '/v', 'Version', '/t', 'REG_SZ', '/d', '14.42.34433', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86', '/v', 'Major', '/t', 'REG_DWORD', '/d', '14', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86', '/v', 'Minor', '/t', 'REG_DWORD', '/d', '42', '/f'],
        // Alternative registry paths that some games check
        ['reg', 'add', 'HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86', '/v', 'Version', '/t', 'REG_SZ', '/d', '14.42.34433', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'],
        // Legacy VC++ versions that games might check
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\DevDiv\\VC\\Servicing\\14.0\\RuntimeMinimum', '/v', 'Install', '/t', 'REG_DWORD', '/d', '1', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\DevDiv\\VC\\Servicing\\14.0\\RuntimeMinimum', '/v', 'Version', '/t', 'REG_SZ', '/d', '14.42.34433', '/f'],
      ];
      
      final wineExecutable = customWineExecutable.isNotEmpty ? customWineExecutable : 'wine';
      
      // Process registry entries and add 'run' prefix if needed for Proton
      final regEntries = baseRegEntries.map((entry) {
        if (isProtonExecutable && !customWineExecutable.endsWith('/wine')) {
          return ['run', ...entry];
        }
        return entry;
      }).toList();
      
      for (final regArgs in regEntries) {
        try {
          final result = await shell.runExecutableArguments(wineExecutable, regArgs);
          if (result.exitCode != 0) {
            logService.log('Failed to create registry entry: ${regArgs.join(' ')}', LogLevel.warning);
            logService.log('Registry error output: ${result.errText}', LogLevel.warning);
          } else {
            logService.log('Successfully created registry entry: ${regArgs.join(' ')}');
          }
        } catch (e) {
          logService.log('Error creating registry entry ${regArgs.join(' ')}: $e', LogLevel.warning);
        }
      }
      
      logService.log('VC++ registry entries created');
      return true;
      
    } catch (e) {
      logService.log('Error creating VC++ registry entries: $e', LogLevel.error);
      return false;
    }
  }
  
  /// Creates comprehensive VC++ registry entries for maximum game compatibility
  Future<bool> _createComprehensiveVcRedistRegistryEntries(WinePrefix prefix, String customWineExecutable, Function(String)? progressCallback) async {
    final logService = LogService();
    
    try {
      progressCallback?.call('Creating comprehensive VC++ registry entries...');
      
      final installEnv = {
        ...Platform.environment,
        'WINEPREFIX': prefix.path,
        'WINEARCH': prefix.architecture,
      };
      
      if (customWineExecutable.isNotEmpty) {
        installEnv['WINE'] = customWineExecutable;
        final wineDir = path.dirname(customWineExecutable);
        installEnv['PATH'] = '$wineDir:${installEnv['PATH'] ?? Platform.environment['PATH'] ?? ''}';
      }
      
      final shell = Shell(environment: installEnv, verbose: true);
      final wineExecutable = customWineExecutable.isNotEmpty ? customWineExecutable : 'wine';
      
      // Check if this is a Proton wine executable that needs 'run' prefix
      final isProtonExecutable = customWineExecutable.isNotEmpty && 
          (customWineExecutable.contains('proton') || customWineExecutable.endsWith('/wine'));
      
      // Comprehensive registry entries covering all common VC++ detection patterns
      final baseRegEntries = [
        // VC++ 2015-2022 x64 (primary)
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64', '/v', 'Version', '/t', 'REG_SZ', '/d', '14.42.34433', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64', '/v', 'Major', '/t', 'REG_DWORD', '/d', '14', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64', '/v', 'Minor', '/t', 'REG_DWORD', '/d', '42', '/f'],
        
        // VC++ 2015-2022 x86
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86', '/v', 'Version', '/t', 'REG_SZ', '/d', '14.42.34433', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86', '/v', 'Major', '/t', 'REG_DWORD', '/d', '14', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86', '/v', 'Minor', '/t', 'REG_DWORD', '/d', '42', '/f'],
        
        // WOW64 entries for x86 detection on 64-bit systems
        ['reg', 'add', 'HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86', '/v', 'Version', '/t', 'REG_SZ', '/d', '14.42.34433', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'],
        
        // Legacy VC++ detection entries
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\DevDiv\\VC\\Servicing\\14.0\\RuntimeMinimum', '/v', 'Install', '/t', 'REG_DWORD', '/d', '1', '/f'],
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\DevDiv\\VC\\Servicing\\14.0\\RuntimeMinimum', '/v', 'Version', '/t', 'REG_SZ', '/d', '14.42.34433', '/f'],
        
        // Additional compatibility entries for older games
        ['reg', 'add', 'HKLM\\SOFTWARE\\Classes\\Installer\\Products', '/f'], // Create Products key
        
        // Legacy VC++ 2005-2013 entries for older games
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\8.0\\VC\\VCRedist\\x64', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'], // 2005
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\9.0\\VC\\VCRedist\\x64', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'], // 2008
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\10.0\\VC\\VCRedist\\x64', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'], // 2010
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\11.0\\VC\\Runtimes\\x64', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'], // 2012
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\12.0\\VC\\Runtimes\\x64', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'], // 2013
        
        // x86 versions
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\8.0\\VC\\VCRedist\\x86', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'], // 2005
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\9.0\\VC\\VCRedist\\x86', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'], // 2008
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\10.0\\VC\\VCRedist\\x86', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'], // 2010
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\11.0\\VC\\Runtimes\\x86', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'], // 2012
        ['reg', 'add', 'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\12.0\\VC\\Runtimes\\x86', '/v', 'Installed', '/t', 'REG_DWORD', '/d', '1', '/f'], // 2013
      ];
      
      // Process registry entries and add 'run' prefix if needed for Proton
      final regEntries = baseRegEntries.map((entry) {
        if (isProtonExecutable && !customWineExecutable.endsWith('/wine')) {
          return ['run', ...entry];
        }
        return entry;
      }).toList();
      
      progressCallback?.call('Creating ${regEntries.length} registry entries for maximum compatibility...');
      
      for (final regArgs in regEntries) {
        try {
          final result = await shell.runExecutableArguments(wineExecutable, regArgs);
          if (result.exitCode != 0 && !regArgs.join(' ').contains('Classes\\Installer\\Products')) {
            // Ignore errors for the Products key creation as it might already exist
            logService.log('Failed to create registry entry: ${regArgs.join(' ')}', LogLevel.warning);
          } else {
            logService.log('Successfully created registry entry: ${regArgs.join(' ')}');
          }
        } catch (e) {
          logService.log('Error creating registry entry ${regArgs.join(' ')}: $e', LogLevel.warning);
        }
      }
      
      logService.log('Comprehensive VC++ registry entries created');
      progressCallback?.call('Comprehensive registry entries created successfully!');
      return true;
      
    } catch (e) {
      logService.log('Error creating comprehensive VC++ registry entries: $e', LogLevel.error);
      return false;
    }
  }

  /// Installs TechPowerUp Visual C++ Redistributable All-in-One package to a Wine prefix
  /// This includes all Visual C++ versions (2005, 2008, 2010, 2012, 2013, 2015-2022)
  /// Enhanced with better installation methods and registry verification
  Future<bool> installVcRedistAllInOne(WinePrefix prefix, Settings settings, {Function(String)? progressCallback, String? customWineExecutable, Map<String, String>? customEnv}) async {
    final logService = LogService();
    // TechPowerUp VC++ All-in-One package direct download
    const vcAllInOneUrl = 'https://files02.tchspt.com/storage2/downloads/VisualCppRedist_AIO_x86_x64_28.11.24.exe';
    Directory? tempDirForVcRedist;
    
    try {
      progressCallback?.call('Downloading TechPowerUp Visual C++ All-in-One package...');
      logService.log('Starting VC++ All-in-One installation for prefix: ${prefix.path}');
      
      tempDirForVcRedist = await Directory.systemTemp.createTemp('vcredist_aio_');
      final vcRedistPath = path.join(tempDirForVcRedist.path, 'VisualCppRedist_AIO.exe');
      
      final dio = Dio();
      await dio.download(vcAllInOneUrl, vcRedistPath, onReceiveProgress: (received, total) {
        if (total > 0) {
          final progressPercent = (received / total * 100).toStringAsFixed(1);
          progressCallback?.call('Downloading VC++ All-in-One: $progressPercent%');
        }
      });
      
      logService.log('VC++ All-in-One package downloaded to $vcRedistPath');
      
      // Verify the downloaded file exists and has reasonable size
      final downloadedFile = File(vcRedistPath);
      if (!await downloadedFile.exists()) {
        throw 'Downloaded file does not exist: $vcRedistPath';
      }
      
      final fileSize = await downloadedFile.length();
      if (fileSize < 1024 * 1024) { // Less than 1MB suggests download failure
        throw 'Downloaded file is too small ($fileSize bytes), likely incomplete';
      }
      
      progressCallback?.call('Download complete (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB), preparing installation...');
      
      // Prepare environment for installation
      final installEnv = {
        ...(Platform.environment),
        ...(customEnv ?? {}),
        'WINEPREFIX': prefix.path,
        'WINEARCH': prefix.architecture,
      };
      
      if (customWineExecutable != null && customWineExecutable.isNotEmpty) {
        installEnv['WINE'] = customWineExecutable;
        final wineDir = path.dirname(customWineExecutable);
        installEnv['PATH'] = '$wineDir:${installEnv['PATH'] ?? Platform.environment['PATH'] ?? ''}';
      }
      
      final shell = Shell(environment: installEnv, verbose: true);
      
      progressCallback?.call('Installing VC++ All-in-One package (this may take several minutes)...');
      logService.log('Installing VC++ All-in-One with command: wine "$vcRedistPath" /ai');
      
      // Try multiple installation methods for better compatibility
      final wineExecutable = customWineExecutable ?? 'wine';
      bool installSuccess = false;
      
      // Method 1: /ai flag (automatic install) - most compatible with TechPowerUp package
      progressCallback?.call('Installing VC++ All-in-One package (method 1/3)...');
      logService.log('Attempting installation with /ai flag');
      
      try {
        final vcInstallResult = await shell.runExecutableArguments(wineExecutable, [
          vcRedistPath, '/ai'
        ]).timeout(Duration(minutes: 15)); // Extended timeout for All-in-One
        
        if (vcInstallResult.exitCode == 0 || vcInstallResult.exitCode == 3010) {
          installSuccess = true;
          logService.log('VC++ All-in-One installed successfully with /ai flag');
        } else {
          throw Exception('Installation failed with exit code ${vcInstallResult.exitCode}');
        }
      } catch (e) {
        logService.log('Method 1 (/ai) failed: $e', LogLevel.warning);
        
        // Method 2: /S flag (silent)
        try {
          progressCallback?.call('Trying silent installation method (method 2/3)...');
          logService.log('Trying /S flag');
          
          final vcInstallResult2 = await shell.runExecutableArguments(wineExecutable, [
            vcRedistPath, '/S'
          ]).timeout(Duration(minutes: 15));
          
          if (vcInstallResult2.exitCode == 0 || vcInstallResult2.exitCode == 3010) {
            installSuccess = true;
            logService.log('VC++ All-in-One installed successfully with /S flag');
          } else {
            throw Exception('Silent installation failed with exit code ${vcInstallResult2.exitCode}');
          }
        } catch (e2) {
          logService.log('Method 2 (/S) failed: $e2', LogLevel.warning);
          
          // Method 3: Interactive mode with timeout (let the installer handle everything)
          try {
            progressCallback?.call('Trying interactive installation (method 3/3)...');
            logService.log('Trying interactive installation mode');
            
            // Set DISPLAY variable to ensure GUI works if available
            final interactiveEnv = {
              ...installEnv,
              if (Platform.environment['DISPLAY'] != null) 'DISPLAY': Platform.environment['DISPLAY']!,
              if (Platform.environment['WAYLAND_DISPLAY'] != null) 'WAYLAND_DISPLAY': Platform.environment['WAYLAND_DISPLAY']!,
            };
            
            final interactiveShell = Shell(environment: interactiveEnv, verbose: true);
            
            final vcInstallResult3 = await interactiveShell.runExecutableArguments(wineExecutable, [
              vcRedistPath
            ]).timeout(Duration(minutes: 20)); // Longer timeout for interactive
            
            if (vcInstallResult3.exitCode == 0 || vcInstallResult3.exitCode == 3010) {
              installSuccess = true;
              logService.log('VC++ All-in-One installed successfully in interactive mode');
            } else {
              final errorMsg = 'VC++ All-in-One installation failed with all methods. Final exit code: ${vcInstallResult3.exitCode}\nStdErr: ${vcInstallResult3.errText}';
              logService.log(errorMsg, LogLevel.error);
            }
          } catch (e3) {
            final errorMsg = 'All VC++ installation methods failed. Last error: $e3';
            logService.log(errorMsg, LogLevel.error);
          }
        }
      }
      
      if (installSuccess) {
        progressCallback?.call('Installation completed, verifying and setting up registry...');
        
        // Create registry entries to ensure games can detect VC++ installations
        await _createVcRedistRegistryEntries(prefix, wineExecutable, progressCallback);
        
        // Verify installation
        final verified = await _verifyVcRedistInstallation(prefix, wineExecutable, progressCallback);
        
        if (verified) {
          progressCallback?.call('All Visual C++ Redistributables installed and verified successfully!');
          return true;
        } else {
          // Installation succeeded but verification failed - still consider it a success
          // but warn that registry entries might need manual attention
          progressCallback?.call('VC++ installed successfully (registry verification incomplete)');
          logService.log('VC++ installation completed but registry verification failed', LogLevel.warning);
          return true;
        }
      } else {
        progressCallback?.call('Error: VC++ All-in-One installation failed with all methods.');
        return false;
      }
      
    } catch (e, stackTrace) {
      final errorMsg = 'Error downloading or installing VC++ All-in-One package: $e';
      logService.log('$errorMsg\n$stackTrace', LogLevel.error);
      progressCallback?.call(errorMsg);
      return false;
    } finally {
      // Clean up temporary directory
      try {
        if (tempDirForVcRedist != null && await tempDirForVcRedist.exists()) {
          await tempDirForVcRedist.delete(recursive: true);
        }
      } catch (e) {
        logService.log('Error cleaning up VC++ All-in-One temp files: $e', LogLevel.warning);
      }
    }
  }

  /// Installs Microsoft Visual C++ Redistributable x86 (2015-2022) to a Wine prefix
  Future<bool> installVcRedistX86(WinePrefix prefix, Settings settings, {Function(String)? progressCallback, String? customWineExecutable, Map<String, String>? customEnv}) async {
    final logService = LogService();
    const vcRedistUrl = 'https://aka.ms/vs/17/release/vc_redist.x86.exe';
    Directory? tempDirForVcRedist;
    
    try {
      progressCallback?.call('Downloading Microsoft Visual C++ Redistributable (x86)...');
      logService.log('Starting VC++ Redistributable (x86) installation for prefix: ${prefix.path}');
      
      tempDirForVcRedist = await Directory.systemTemp.createTemp('vcredist_x86_');
      final vcRedistPath = path.join(tempDirForVcRedist.path, 'vc_redist.x86.exe');
      
      final dio = Dio();
      await dio.download(vcRedistUrl, vcRedistPath, onReceiveProgress: (received, total) {
        if (total > 0) {
          final progressPercent = (received / total * 100).toStringAsFixed(1);
          progressCallback?.call('Downloading VC++ Redist (x86): $progressPercent%');
        }
      });
      
      logService.log('VC++ Redistributable (x86) downloaded to $vcRedistPath');
      
      // Prepare environment for installation
      final installEnv = {
        ...(Platform.environment),
        ...(customEnv ?? {}),
        'WINEPREFIX': prefix.path,
        'WINEARCH': prefix.architecture,
      };
      
      if (customWineExecutable != null && customWineExecutable.isNotEmpty) {
        installEnv['WINE'] = customWineExecutable;
        final wineDir = path.dirname(customWineExecutable);
        installEnv['PATH'] = '$wineDir:${installEnv['PATH'] ?? Platform.environment['PATH'] ?? ''}';
      }
      
      final shell = Shell(environment: installEnv, verbose: true);
      
      progressCallback?.call('Installing VC++ Redistributable (x86)...');
      logService.log('Installing VC++ Redistributable (x86) with command: wine "$vcRedistPath" /install /passive /norestart');
      
      final wineExecutable = customWineExecutable ?? 'wine';
      bool installSuccess = false;
      
      // Check if this is a Proton wine executable that needs 'run' prefix
      final isProtonExecutable = customWineExecutable != null && 
          (customWineExecutable.contains('proton') || customWineExecutable.endsWith('/wine'));
      
      // Try multiple installation methods for better compatibility
      // Method 1: /install /passive /norestart
      List<String> vcInstallArgs;
      if (isProtonExecutable && !customWineExecutable!.endsWith('/wine')) {
        // For true Proton scripts, use 'run' prefix
        vcInstallArgs = ['run', vcRedistPath, '/install', '/passive', '/norestart'];
      } else {
        // For Wine executables or system wine, run directly
        vcInstallArgs = [vcRedistPath, '/install', '/passive', '/norestart'];
      }
      
      final vcInstallResult = await shell.runExecutableArguments(wineExecutable, vcInstallArgs);
      
      if (vcInstallResult.exitCode == 0 || vcInstallResult.exitCode == 3010) {
        installSuccess = true;
        logService.log('VC++ Redistributable (x86) installed successfully with /passive flag');
      } else {
        // Method 2: /quiet /norestart
        progressCallback?.call('Trying alternative installation method...');
        logService.log('Trying /quiet installation method for VC++ x86');
        
        List<String> vcInstallArgs2;
        if (isProtonExecutable && !customWineExecutable!.endsWith('/wine')) {
          vcInstallArgs2 = ['run', vcRedistPath, '/quiet', '/norestart'];
        } else {
          vcInstallArgs2 = [vcRedistPath, '/quiet', '/norestart'];
        }
        
        final vcInstallResult2 = await shell.runExecutableArguments(wineExecutable, vcInstallArgs2);
        
        if (vcInstallResult2.exitCode == 0 || vcInstallResult2.exitCode == 3010) {
          installSuccess = true;
          logService.log('VC++ Redistributable (x86) installed successfully with /quiet flag');
        } else {
          // Method 3: GUI mode
          progressCallback?.call('Trying interactive installation...');
          logService.log('Trying GUI installation mode for VC++ x86');
          
          List<String> vcInstallArgs3;
          if (isProtonExecutable && !customWineExecutable!.endsWith('/wine')) {
            vcInstallArgs3 = ['run', vcRedistPath];
          } else {
            vcInstallArgs3 = [vcRedistPath];
          }
          
          final vcInstallResult3 = await shell.runExecutableArguments(wineExecutable, vcInstallArgs3);
          
          if (vcInstallResult3.exitCode == 0 || vcInstallResult3.exitCode == 3010) {
            installSuccess = true;
            logService.log('VC++ Redistributable (x86) installed successfully in GUI mode');
          }
        }
      }
      
      if (installSuccess) {
        // Create registry entries for better compatibility
        await _createVcRedistRegistryEntries(prefix, wineExecutable, progressCallback);
        progressCallback?.call('VC++ Redistributable (x86) installed successfully.');
        return true;
      } else {
        final errorMsg = 'VC++ Redistributable (x86) installation failed with all methods. Last exit code: ${vcInstallResult.exitCode}\nStdErr: ${vcInstallResult.errText}';
        logService.log(errorMsg, LogLevel.error);
        progressCallback?.call('Error: VC++ Redistributable (x86) installation failed.');
        return false;
      }
      
    } catch (e, stackTrace) {
      final errorMsg = 'Error downloading or installing VC++ Redistributable (x86): $e';
      logService.log('$errorMsg\n$stackTrace', LogLevel.error);
      progressCallback?.call(errorMsg);
      return false;
    } finally {
      // Clean up temporary directory
      try {
        if (tempDirForVcRedist != null && await tempDirForVcRedist.exists()) {
          await tempDirForVcRedist.delete(recursive: true);
        }
      } catch (e) {
        logService.log('Error cleaning up VC++ Redist temp files: $e', LogLevel.warning);
      }
    }
  }

  /// Installs Microsoft Visual C++ Redistributable via Winetricks (vcrun2019)
  Future<bool> installVcRunViaTricks2019(WinePrefix prefix, Settings settings, {Function(String)? progressCallback, String? customWineExecutable, Map<String, String>? customEnv}) async {
    final logService = LogService();
    
    try {
      progressCallback?.call('Installing Visual C++ 2015-2022 Redistributable via Winetricks (vcrun2019)...');
      logService.log('Starting vcrun2019 installation via Winetricks for prefix: ${prefix.path}');
      
      // Use the existing installComponent method with vcrun2019
      try {
        await installComponent(
          prefix, 
          'vcrun2019',
          progressCallback: progressCallback,
          customWineExecutable: customWineExecutable,
          customEnv: customEnv
        );
        
        progressCallback?.call('Visual C++ Redistributable (vcrun2019) installed via Winetricks.');
        logService.log('vcrun2019 installation completed successfully');
        return true;
      } catch (winetricksError) {
        logService.log('Winetricks vcrun2019 failed, falling back to direct installation: $winetricksError', LogLevel.warning);
        progressCallback?.call('Winetricks failed, attempting direct VC++ x64 installation...');
        
        // Fallback to direct installation
        return await installVcRedistX64(prefix, settings, 
          progressCallback: progressCallback,
          customWineExecutable: customWineExecutable,
          customEnv: customEnv
        );
      }
      
    } catch (e, stackTrace) {
      final errorMsg = 'Error installing Visual C++ via Winetricks (vcrun2019): $e';
      logService.log('$errorMsg\n$stackTrace', LogLevel.error);
      progressCallback?.call(errorMsg);
      return false;
    }
  }

  /// Installs Microsoft Visual C++ Redistributable via Winetricks (vcrun2022)
  Future<bool> installVcRunViaTricks2022(WinePrefix prefix, Settings settings, {Function(String)? progressCallback, String? customWineExecutable, Map<String, String>? customEnv}) async {
    final logService = LogService();
    
    try {
      progressCallback?.call('Installing Visual C++ 2022 Redistributable via Winetricks (vcrun2022)...');
      logService.log('Starting vcrun2022 installation via Winetricks for prefix: ${prefix.path}');
      
      // Use the existing installComponent method with vcrun2022
      try {
        await installComponent(
          prefix, 
          'vcrun2022',
          progressCallback: progressCallback,
          customWineExecutable: customWineExecutable,
          customEnv: customEnv
        );
        
        progressCallback?.call('Visual C++ Redistributable (vcrun2022) installed via Winetricks.');
        logService.log('vcrun2022 installation completed successfully');
        return true;
      } catch (winetricksError) {
        logService.log('Winetricks vcrun2022 failed, falling back to direct installation: $winetricksError', LogLevel.warning);
        progressCallback?.call('Winetricks failed, attempting direct VC++ x64 installation...');
        
        // Fallback to direct installation
        return await installVcRedistX64(prefix, settings, 
          progressCallback: progressCallback,
          customWineExecutable: customWineExecutable,
          customEnv: customEnv
        );
      }
      
    } catch (e, stackTrace) {
      final errorMsg = 'Error installing Visual C++ via Winetricks (vcrun2022): $e';
      logService.log('$errorMsg\n$stackTrace', LogLevel.error);
      progressCallback?.call(errorMsg);
      return false;
    }
  }

  /// Comprehensive VC++ installation using official Microsoft redistributables
  Future<bool> installAllVcppRedistributablesComprehensive(WinePrefix prefix, Settings settings, {Function(String)? progressCallback, String? customWineExecutable, Map<String, String>? customEnv}) async {
    final logService = LogService();
    
    try {
      progressCallback?.call('Installing Microsoft Visual C++ Redistributables (2015-2022)...');
      logService.log('Starting comprehensive VC++ installation for prefix: ${prefix.path}');
      
      // Install the latest Microsoft Visual C++ redistributables (covers 2015-2022)
      // These are the most commonly needed and cover the vast majority of games
      
      bool x64Success = false;
      bool x86Success = false;
      
      // Install x64 version first
      try {
        progressCallback?.call('Installing VC++ 2015-2022 Redistributable (x64)...');
        x64Success = await installVcRedistX64(prefix, settings, 
          progressCallback: progressCallback,
          customWineExecutable: customWineExecutable,
          customEnv: customEnv
        );
        if (x64Success) {
          logService.log('Successfully installed VC++ x64 redistributable');
        }
      } catch (e) {
        logService.log('Failed to install VC++ x64: $e', LogLevel.warning);
      }
      
      // Install x86 version 
      try {
        progressCallback?.call('Installing VC++ 2015-2022 Redistributable (x86)...');
        x86Success = await installVcRedistX86(prefix, settings, 
          progressCallback: progressCallback,
          customWineExecutable: customWineExecutable,
          customEnv: customEnv
        );
        if (x86Success) {
          logService.log('Successfully installed VC++ x86 redistributable');
        }
      } catch (e) {
        logService.log('Failed to install VC++ x86: $e', LogLevel.warning);
      }
      
      // Create additional registry entries for better compatibility
      if (x64Success || x86Success) {
        progressCallback?.call('Creating comprehensive registry entries...');
        await _createComprehensiveVcRedistRegistryEntries(prefix, customWineExecutable ?? 'wine', progressCallback);
      }
      
      if (x64Success || x86Success) {
        progressCallback?.call('Visual C++ Redistributables installed successfully!');
        logService.log('VC++ comprehensive installation completed for prefix: ${prefix.path}');
        return true;
      } else {
        progressCallback?.call('Failed to install any Visual C++ redistributables.');
        logService.log('All VC++ installations failed for prefix: ${prefix.path}', LogLevel.error);
        return false;
      }
      
    } catch (e, stackTrace) {
      final errorMsg = 'Error during comprehensive VC++ installation: $e';
      logService.log('$errorMsg\n$stackTrace', LogLevel.error);
      progressCallback?.call(errorMsg);
      return false;
    }
  }

  /// Installs multiple VC++ runtimes via Winetricks for maximum compatibility
  Future<bool> installVcRunViaTricsAll(WinePrefix prefix, Settings settings, {Function(String)? progressCallback, String? customWineExecutable, Map<String, String>? customEnv}) async {
    final logService = LogService();
    
    try {
      progressCallback?.call('Installing multiple Visual C++ Redistributables via Winetricks...');
      logService.log('Starting comprehensive VC++ installation via Winetricks for prefix: ${prefix.path}');
      
      final vcComponents = ['vcrun2019', 'vcrun2022', 'vcrun2017', 'vcrun2015'];
      final installedComponents = <String>[];
      final failedComponents = <String>[];
      
      for (final component in vcComponents) {
        try {
          progressCallback?.call('Installing $component via Winetricks...');
          await installComponent(
            prefix, 
            component,
            progressCallback: progressCallback,
            customWineExecutable: customWineExecutable,
            customEnv: customEnv
          );
          installedComponents.add(component);
          logService.log('Successfully installed $component via Winetricks');
        } catch (e) {
          failedComponents.add(component);
          logService.log('Failed to install $component via Winetricks: $e', LogLevel.warning);
          progressCallback?.call('Warning: Failed to install $component, continuing...');
          
          // For critical components, try fallback
          if (component == 'vcrun2019' || component == 'vcrun2022') {
            try {
              progressCallback?.call('Attempting fallback installation for $component...');
              final fallbackSuccess = await installVcRedistX64(prefix, settings, 
                progressCallback: progressCallback,
                customWineExecutable: customWineExecutable,
                customEnv: customEnv
              );
              
              if (fallbackSuccess) {
                failedComponents.remove(component);
                installedComponents.add(component);
                logService.log('Successfully installed $component via fallback method');
                progressCallback?.call('$component installed via fallback method.');
              }
            } catch (fallbackError) {
              logService.log('Fallback installation also failed for $component: $fallbackError', LogLevel.warning);
            }
          }
        }
      }
      
      final successCount = installedComponents.length;
      final totalCount = vcComponents.length;
      
      if (successCount > 0) {
        progressCallback?.call('Installed $successCount/$totalCount VC++ redistributables via Winetricks.');
        logService.log('VC++ installation via Winetricks completed: $successCount/$totalCount successful');
        return true;
      } else {
        progressCallback?.call('Failed to install any VC++ redistributables via Winetricks.');
        logService.log('All VC++ installations failed via Winetricks', LogLevel.error);
        return false;
      }
      
    } catch (e, stackTrace) {
      final errorMsg = 'Error installing Visual C++ redistributables via Winetricks: $e';
      logService.log('$errorMsg\n$stackTrace', LogLevel.error);
      progressCallback?.call(errorMsg);
      return false;
    }
  }

  /// Installs common dependencies for older games like Tiger Woods PGA TOUR 06
  Future<bool> installLegacyGameDependencies(WinePrefix prefix, Settings settings, {Function(String)? progressCallback, String? customWineExecutable, Map<String, String>? customEnv}) async {
    final logService = LogService();
    
    try {
      progressCallback?.call('Installing legacy game dependencies...');
      logService.log('Starting legacy game dependencies installation for prefix: ${prefix.path}');
      
      // Install TechPowerUp VC++ All-in-One (includes all versions - better for legacy games)
      progressCallback?.call('Installing all Visual C++ Redistributables for legacy game support...');
      final vcAllInOneSuccess = await installVcRedistAllInOne(prefix, settings, 
        progressCallback: progressCallback, 
        customWineExecutable: customWineExecutable, 
        customEnv: customEnv
      );
      
      if (!vcAllInOneSuccess) {
        logService.log('VC++ All-in-One installation failed, trying individual x86 installation...', LogLevel.warning);
        
        // Fallback to x86 only if all-in-one fails
        final vcX86Success = await installVcRedistX86(prefix, settings, 
          progressCallback: progressCallback, 
          customWineExecutable: customWineExecutable, 
          customEnv: customEnv
        );
        
        if (!vcX86Success) {
          logService.log('Both VC++ All-in-One and x86 installations failed, continuing...', LogLevel.warning);
        }
      }
      
      // Install common Winetricks dependencies for legacy games
      final legacyDeps = [
        'directplay',        // For older DirectX multiplayer games
        'dsound',           // DirectSound
        'mfc42',            // Microsoft Foundation Classes
        'vcrun6',           // Visual C++ 6.0 runtime
        'vcrun2005',        // Visual C++ 2005 runtime
        'vcrun2008',        // Visual C++ 2008 runtime
        'physx',            // PhysX for games that need it
      ];
      
      progressCallback?.call('Installing Winetricks dependencies for legacy games...');
      for (final dep in legacyDeps) {
        try {
          progressCallback?.call('Installing $dep...');
          await installComponent(prefix, dep, 
            progressCallback: progressCallback,
            customWineExecutable: customWineExecutable,
            customEnv: customEnv
          );
          logService.log('Successfully installed legacy dependency: $dep');
        } catch (e) {
          logService.log('Failed to install legacy dependency $dep: $e', LogLevel.warning);
          progressCallback?.call('Warning: Failed to install $dep, continuing...');
        }
      }
      
      progressCallback?.call('Legacy game dependencies installation completed.');
      logService.log('Legacy game dependencies installation completed for prefix: ${prefix.path}');
      return true;
      
    } catch (e, stackTrace) {
      final errorMsg = 'Error installing legacy game dependencies: $e';
      logService.log('$errorMsg\n$stackTrace', LogLevel.error);
      progressCallback?.call(errorMsg);
      return false;
    }
  }

  /// Installs a component (verb) using winetricks into the specified prefix with timeout handling.
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
      
      // Add timeout for winetricks operations that might hang
      final timeout = Duration(minutes: 10); // 10 minute timeout
      
      try {
        final results = await shell.run(command).timeout(timeout);
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
          
          // For VC++ components, try alternative installation if main one fails
          if (component.startsWith('vcrun')) {
            progressCallback?.call('Winetricks installation failed, this may be due to wow64 compatibility issues.');
            logService.log('VC++ component $component failed via winetricks, may need alternative installation method');
            throw Exception('Winetricks $component installation failed with exit code ${result.exitCode}');
          }
        }
      } on TimeoutException {
        progressCallback?.call('$component installation timed out (10 minutes). This may be due to hanging processes.');
        logService.log('Winetricks $component installation timed out after 10 minutes', LogLevel.error);
        
        // Try to kill any hanging wine processes
        try {
          await Process.run('pkill', ['-f', 'vc_redist']);
          await Process.run('pkill', ['-f', component]);
          // Kill wineserver for this prefix
          final wineServerKill = Shell(environment: winetricksEnv, verbose: false);
          await wineServerKill.run('wineserver -k');
        } catch (killError) {
          logService.log('Error killing hanging processes: $killError', LogLevel.warning);
        }
        
        throw Exception('Winetricks $component installation timed out');
      }
    } catch (e, stackTrace) {
      progressCallback?.call('Error installing $component with Winetricks: $e');
      logService.log('Exception during Winetricks $component installation: $e\n$stackTrace', LogLevel.error);
      
      // Clean up any hanging processes
      try {
        await Process.run('pkill', ['-f', 'vc_redist']);
        await Process.run('pkill', ['-f', component]);
        final wineServerKill = Shell(environment: winetricksEnv, verbose: false);
        await wineServerKill.run('wineserver -k');
      } catch (killError) {
        logService.log('Error during cleanup: $killError', LogLevel.warning);
      }
      
      throw Exception('Winetricks $component installation failed: $e');
    }
  }

  /// Wrapper method for installDxvk to maintain backwards compatibility
  Future<bool> installDXVK(WinePrefix prefix, {Function(String)? progressCallback}) async {
    // Get settings from the prefix's path
    final settings = Settings(
      prefixDirectory: path.dirname(prefix.path),
      categories: const [],
      igdbImageBaseUrl: 'https://images.igdb.com/igdb/image/upload/',
    );
    return installDxvk(prefix, settings, progressCallback: progressCallback);
  }

  /// Wrapper method for installVkd3d to maintain backwards compatibility
  Future<bool> installVKD3D(WinePrefix prefix, {Function(String)? progressCallback}) async {
    // Get settings from the prefix's path
    final settings = Settings(
      prefixDirectory: path.dirname(prefix.path),
      categories: const [],
      igdbImageBaseUrl: 'https://images.igdb.com/igdb/image/upload/',
    );
    return installVkd3d(prefix, settings, progressCallback: progressCallback);
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
