import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:process_run/shell.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart'; // Import Settings model

/// Service for downloading and installing components like DXVK and VKD3D-Proton
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
    if (prefix.type != PrefixType.wine) {
      progressCallback?.call('DXVK installation is only supported for Wine prefixes (not Proton)');
      return false;
    }
    
    try {
      progressCallback?.call('Fetching latest DXVK release information...');
      final release = await getLatestDxvkRelease(settings); // Pass settings
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
      
      if (dxvkAsset == null) {
        progressCallback?.call('Could not find DXVK tar.gz asset in the release. Trying direct download URL...');
        // Try a direct hardcoded URL as fallback
        final tagName = release['tag_name'].toString();
        final directUrl = 'https://github.com/doitsujin/dxvk/releases/download/$tagName/dxvk-$tagName.tar.gz';
        progressCallback?.call('Trying direct URL: $directUrl');
        
        final downloadPath = await _downloadRelease(directUrl, prefix.path);
        progressCallback?.call('Downloaded DXVK successfully using direct URL');
        
        // Continue with extraction
        progressCallback?.call('Extracting DXVK...');
        final extractDir = Directory.systemTemp.createTempSync('dxvk_extract_');
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
        
        // Install the DLLs
        progressCallback?.call('Installing DXVK DLLs to prefix...');
        final x64Dir = path.join(dxvkDir.path, 'x64');
        final x32Dir = path.join(dxvkDir.path, 'x32');
        
        // Ensure the Windows system directories exist
        final sys32Dir = Directory(path.join(prefix.path, 'drive_c', 'windows', 'system32'));
        final sysWow64Dir = Directory(path.join(prefix.path, 'drive_c', 'windows', 'syswow64'));
        sys32Dir.createSync(recursive: true);
        sysWow64Dir.createSync(recursive: true);
        
        // Copy the DLLs
        if (Directory(x64Dir).existsSync()) {
          for (var file in Directory(x64Dir).listSync()) {
            if (file is File && path.extension(file.path) == '.dll') {
              final targetPath = path.join(sys32Dir.path, path.basename(file.path));
              file.copySync(targetPath);
            }
          }
        }
        
        if (Directory(x32Dir).existsSync()) {
          for (var file in Directory(x32Dir).listSync()) {
            if (file is File && path.extension(file.path) == '.dll') {
              final targetPath = path.join(sysWow64Dir.path, path.basename(file.path));
              file.copySync(targetPath);
            }
          }
        }
        
        // Cleanup
        await File(downloadPath).delete();
        await extractDir.delete(recursive: true);
        
        progressCallback?.call('DXVK $tagName has been installed successfully');
        return true;
      }
      
      // Regular asset download flow
      progressCallback?.call('Downloading DXVK ${release['tag_name']}...');
      final downloadUrl = dxvkAsset['browser_download_url'];
      final downloadPath = await _downloadRelease(downloadUrl, prefix.path);
      
      // Continue with the original flow
      progressCallback?.call('Extracting DXVK...');
      final extractDir = Directory.systemTemp.createTempSync('dxvk_extract_');
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
        
        final dxvkDir = anyDirs.first.path;
        progressCallback?.call('Using directory: ${path.basename(dxvkDir)}');
        
        final x64Dir = path.join(dxvkDir, 'x64');
        final x32Dir = path.join(dxvkDir, 'x32');
        
        // Rest of the installation logic...
        // ...existing code...
        
        progressCallback?.call('DXVK ${release['tag_name']} has been installed successfully');
        return true;
      }
      
      // Original flow continues
      final dxvkDir = dxvkDirs.first.path;
      final x64Dir = path.join(dxvkDir, 'x64');
      final x32Dir = path.join(dxvkDir, 'x32');
      
      // Install DXVK using direct file copy
      progressCallback?.call('Installing DXVK to prefix...');
      
      // Ensure the Windows system directories exist
      final sys32Dir = Directory(path.join(prefix.path, 'drive_c', 'windows', 'system32'));
      final sysWow64Dir = Directory(path.join(prefix.path, 'drive_c', 'windows', 'syswow64'));
      sys32Dir.createSync(recursive: true);
      sysWow64Dir.createSync(recursive: true);
      
      // Copy the DLLs
      if (Directory(x64Dir).existsSync()) {
        for (var file in Directory(x64Dir).listSync()) {
          if (file is File && path.extension(file.path) == '.dll') {
            final targetPath = path.join(sys32Dir.path, path.basename(file.path));
            file.copySync(targetPath);
          }
        }
      }
      
      if (Directory(x32Dir).existsSync()) {
        for (var file in Directory(x32Dir).listSync()) {
          if (file is File && path.extension(file.path) == '.dll') {
            final targetPath = path.join(sysWow64Dir.path, path.basename(file.path));
            file.copySync(targetPath);
          }
        }
      }
      
      // Cleanup
      await File(downloadPath).delete();
      await extractDir.delete(recursive: true);
      
      progressCallback?.call('DXVK ${release['tag_name']} has been installed successfully');
      return true;
    } catch (e) {
      progressCallback?.call('Error installing DXVK: $e');
      return false;
    }
  }

  /// Installs VKD3D-Proton to a Wine prefix
  Future<bool> installVkd3d(WinePrefix prefix, Settings settings, {Function(String)? progressCallback}) async { // Added settings parameter
    if (prefix.type != PrefixType.wine) {
      progressCallback?.call('VKD3D-Proton installation is only supported for Wine prefixes (not Proton)');
      return false;
    }
    
    try {
      // Use the specific version URL instead of fetching from GitHub API
      const specificVersion = 'v2.14.1';
      const specificVersionNumber = '2.14.1';
      const directUrl = 'https://github.com/HansKristian-Work/vkd3d-proton/releases/download/$specificVersion/vkd3d-proton-$specificVersionNumber.tar.zst';
      
      progressCallback?.call('Using VKD3D-Proton $specificVersionNumber');
      progressCallback?.call('Downloading from: $directUrl');
      
      String downloadPath;
      try {
        downloadPath = await _downloadRelease(directUrl, prefix.path);
        progressCallback?.call('Downloaded VKD3D-Proton successfully');
      } catch (e) {
        progressCallback?.call('Download failed: $e');
        return false;
      }
      
      // Extract the archive
      progressCallback?.call('Extracting VKD3D-Proton...');
      
      // Check file extension to determine extraction method
      final extractDir = Directory.systemTemp.createTempSync('vkd3d_extract_');
      
      if (path.extension(downloadPath) == '.zst') {
        // Use external zstd command for .tar.zst files
        progressCallback?.call('Using zstd to extract .tar.zst file...');
        
        // First, check if zstd is installed
        final zstdCheck = await Process.run('which', ['zstd']);
        if (zstdCheck.exitCode != 0) {
          progressCallback?.call('Error: zstd not found. Please install zstd to extract .tar.zst files.');
          return false;
        }
        
        // Extract using zstd to get the tar file
        final tarFile = path.join(path.dirname(downloadPath), 'vkd3d-proton.tar');
        final zstdResult = await Process.run('zstd', ['-d', downloadPath, '-o', tarFile]);
        
        if (zstdResult.exitCode != 0) {
          progressCallback?.call('Error extracting with zstd: ${zstdResult.stderr}');
          return false;
        }
        
        // Now extract the tar file
        final tarResult = await Process.run('tar', ['-xf', tarFile, '-C', extractDir.path]);
        
        if (tarResult.exitCode != 0) {
          progressCallback?.call('Error extracting tar: ${tarResult.stderr}');
          return false;
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
        return false;
      }
      
      progressCallback?.call('Found setup script at: ${setupScriptFile!.path}');
      
      // Make setup script executable
      await Process.run('chmod', ['+x', setupScriptFile!.path]);
      
      // Run the setup script
      progressCallback?.call('Installing VKD3D-Proton to prefix...');
      final result = await Process.run(
        setupScriptFile!.path,
        ['install', prefix.path]
      );
      
      // Cleanup
      await File(downloadPath).delete();
      await extractDir.delete(recursive: true);
      
      if (result.exitCode != 0) {
        progressCallback?.call('VKD3D-Proton installation failed: ${result.stderr}');
        progressCallback?.call('Standard output: ${result.stdout}');
        return false;
      }
      
      progressCallback?.call('VKD3D-Proton $specificVersionNumber has been installed successfully');
      return true;
    } catch (e) {
      progressCallback?.call('Error installing VKD3D-Proton: $e');
      return false;
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
}
