import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:process_run/shell.dart'; // Import Shell
import '../models/settings.dart';
import '../models/prefix_models.dart';
import 'log_service.dart'; // Add log service import
import 'package:http/http.dart' as http;
import 'wine_component_installer.dart'; // Add import for WineComponentInstaller

class PrefixManagementService {
  final LogService _logService = LogService(); // Add log service

  PrefixManagementService() {
    _initializeLogService();
  }

  Future<void> _initializeLogService() async {
    try {
      await _logService.initialize();
    } catch (e) {
      // If the initialization fails, we'll continue without logging
      print('Error initializing LogService: $e');
    }
  }

  /// Scans the prefix directory specified in settings for existing Wine/Proton prefixes.
  /// Returns a list of discovered WinePrefix objects.
  Future<List<WinePrefix>> scanForExistingPrefixes(Settings settings) async {
    List<WinePrefix> foundPrefixes = [];
    final prefixBaseDir = settings.prefixDirectory; // Use the primary directory for scanning
    
    _logService.log('Scanning for prefixes in: $prefixBaseDir');

    if (prefixBaseDir.isEmpty || !await Directory(prefixBaseDir).exists()) {
      // Prefix directory not set or does not exist. Cannot scan.
      _logService.log('Prefix directory not set or does not exist: $prefixBaseDir', LogLevel.warning);
      return foundPrefixes; // Return empty list if base directory is invalid
    }

    // Define the prefix type subdirectories to scan
    List<String> typeSubdirs = [
      '', // Also scan root for legacy prefixes
      'custom',
      'wine',
      'proton',
      'proton-ge',
      'proton-kronek',
    ];

    // Scanning for prefixes in specified directories
    for (final typeSubdir in typeSubdirs) {
      final scanDir = typeSubdir.isEmpty 
          ? prefixBaseDir 
          : path.join(prefixBaseDir, typeSubdir);
      
      if (!await Directory(scanDir).exists()) {
        _logService.log('Skipping non-existent subdirectory: $scanDir');
        continue; // Skip if subdirectory doesn't exist
      }
      
      _logService.log('Scanning subdirectory: $scanDir');
      
      try {
        await for (final entry in Directory(scanDir).list()) {
          if (entry is Directory) {
            _logService.log('Checking directory: ${entry.path}');
            final prefixName = path.basename(entry.path);

            // --- Check for registry files ---
            final systemRegPath = path.join(entry.path, 'system.reg');
            final userRegPath = path.join(entry.path, 'user.reg');
            final systemRegExists = await File(systemRegPath).exists();
            final userRegExists = await File(userRegPath).exists();

            // Declare variables needed in multiple scopes
            String? buildPath;
            PrefixType type = PrefixType.wine; // Default to wine
            bool foundRegFiles = systemRegExists || userRegExists; // Flag if .reg found in root
            
            if (foundRegFiles) {
              _logService.log('Found registry files in root directory: ${entry.path}');
            }

            // If not found in root, check inside 'pfx' subdirectory
            if (!foundRegFiles) {
              final pfxPath = path.join(entry.path, 'pfx');
              if (await Directory(pfxPath).exists()) {
                final systemRegPfxPath = path.join(pfxPath, 'system.reg');
                final userRegPfxPath = path.join(pfxPath, 'user.reg');
                final systemRegPfxExists = await File(systemRegPfxPath).exists();
                final userRegPfxExists = await File(userRegPfxPath).exists();
                if (systemRegPfxExists || userRegPfxExists) {
                  // Found potential prefix nested in pfx
                  foundRegFiles = true; // Mark as found
                  _logService.log('Found registry files in pfx subdirectory: $pfxPath');
                }
              }
            }
            // --- End Check for registry files ---

            // Also check for drive_c directory as fallback
            if (!foundRegFiles) {
              final driveCPath = path.join(entry.path, 'drive_c');
              if (await Directory(driveCPath).exists()) {
                foundRegFiles = true; // Consider this a valid prefix if it has a drive_c directory
                _logService.log('No registry files found, but found drive_c directory: $driveCPath');
              }
            }

            // --- Process if registry files were found ---
            if (foundRegFiles) {
              _logService.log('Processing prefix: ${entry.path}');

              // Config file should always be in the root directory (entry.path)
              final configFile = File(path.join(entry.path, '.prefix_config'));

              if (await configFile.exists()) {
                try {
                  final configContent = await configFile.readAsString();
                  _logService.log('Config file content: $configContent');
                  final config = json.decode(configContent);
                  buildPath = config['buildPath'] as String?;
                  final typeString = config['type'] as String? ?? 'PrefixType.wine'; // Read type or default to wine
                  _logService.log('Read from config - buildPath: $buildPath, type: $typeString');
                  
                  if (typeString == 'PrefixType.proton') {
                    type = PrefixType.proton;
                  } else if (typeString == 'PrefixType.custom' || typeString == 'PrefixType.gaming') {
                    type = PrefixType.custom;
                  } else {
                    type = PrefixType.wine; // Default to wine for unknown or "PrefixType.wine"
                  }
                  _logService.log('Determined prefix type: ${type.name}');
                } catch (e) {
                   _logService.log('Error reading config file: $e', LogLevel.error);
                   // Proceed without build path if config is corrupt
                }
              } else {
                // Config file (.prefix_config) not found. Attempting to recreate.
                _logService.log('Config file not found. Recreating based on directory structure.');
                // Guess type based on subdirectory and name
                if (typeSubdir.contains('proton') || prefixName.toLowerCase().contains('proton')) {
                  type = PrefixType.proton;
                } else if (typeSubdir == 'custom') {
                  type = PrefixType.custom;
                } else if (typeSubdir == 'wine') {
                  type = PrefixType.wine;
                } else {
                  type = PrefixType.wine; // Default guess
                }
                buildPath = null; // Cannot determine build path

                // Create default config content
                final defaultConfig = {
                  'buildPath': buildPath,
                  'type': type.toString(), // Use enum name directly
                  // Add other default fields if necessary in the future
                };

                try {
                  await configFile.writeAsString(json.encode(defaultConfig));
                  _logService.log('Created default .prefix_config with type: ${type.name}');
                } catch (e) {
                  _logService.log('Failed to create default .prefix_config: $e', LogLevel.error);
                  // Proceed without config if creation fails
                }
              }

              // Create the WinePrefix object
              // Note: ExeEntries are loaded separately (e.g., by PrefixStorageService)
              final prefix = WinePrefix(
                name: prefixName,
                path: entry.path, // Use the main directory path for the prefix object
                wineBuildPath: buildPath ?? '', // Use empty string if not found
                type: type,
                exeEntries: [], // Scanner doesn't load exe entries
              );
              foundPrefixes.add(prefix);
              _logService.log('Added prefix: ${prefix.name}, type: ${prefix.type.name}, path: ${prefix.path}');

            } else {
              _logService.log('Skipping directory (no system.reg, user.reg, or drive_c found): ${entry.path}', LogLevel.warning);
            }
            // --- End Process if registry files were found ---
          }
        }
      } catch (e) {
        _logService.log('Error scanning subdirectory $scanDir: $e', LogLevel.error);
        // Continue with other subdirectories
      }
    }

    _logService.log('Scan complete. Found ${foundPrefixes.length} prefixes.');
    return foundPrefixes;
  }


  /// Deletes the specified prefix directory recursively.
  /// Returns true if successful, false otherwise.
  Future<bool> deletePrefixDirectory(String prefixPath) async {
    try {
      final dir = Directory(prefixPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        // Deleted prefix directory
        return true;
      } else {
        // Prefix directory not found, nothing to delete
        return true; // Consider it success if it doesn't exist
      }
    } catch (e) {
      // Error deleting prefix directory
      return false;
    }
  }

  /// Renames the specified prefix directory.
  /// Returns the new path if successful, throws an exception otherwise.
  Future<String> renamePrefixDirectory(String currentPrefixPath, String newPrefixName) async {
    final currentDir = Directory(currentPrefixPath);
    if (!await currentDir.exists()) {
      throw Exception('Prefix directory to rename does not exist: $currentPrefixPath');
    }

    final parentDir = currentDir.parent.path;
    final newPrefixPath = path.join(parentDir, newPrefixName);
    final newDir = Directory(newPrefixPath);

    if (await newDir.exists()) {
      throw Exception('A directory with the new name already exists: $newPrefixPath');
    }
    if (newPrefixName.contains('/') || newPrefixName.contains('\\')) {
       throw Exception('New prefix name cannot contain slashes.');
    }

    try {
      await currentDir.rename(newPrefixPath);
      // Renamed prefix directory
      return newPrefixPath; // Return the new path
    } catch (e) {
      // Error renaming prefix directory
      throw Exception('Failed to rename prefix directory: $e');
    }
  }

  /// Moves a game's folder (parent directory of the executable) to a new parent directory.
  /// Returns the new path of the executable.
  Future<String> moveGameFolder(String currentExePath, String destinationParentDir) async {
    final sourceDir = Directory(path.dirname(currentExePath));
    final sourceDirName = path.basename(sourceDir.path);
    final destinationDir = Directory(path.join(destinationParentDir, sourceDirName));

    if (!await sourceDir.exists()) {
      throw Exception('Source directory does not exist: ${sourceDir.path}');
    }
    if (await destinationDir.exists()) {
      throw Exception('Destination directory already exists: ${destinationDir.path}');
    }
    if (sourceDir.path == destinationDir.path) {
       throw Exception('Source and destination directories are the same.');
    }

    try {
      // Moving directory
      // Ensure destination parent exists
      await Directory(destinationParentDir).create(recursive: true);
      // Rename (move) the directory
      await sourceDir.rename(destinationDir.path);

      // Calculate the new executable path
      final exeFilename = path.basename(currentExePath);
      final newExePath = path.join(destinationDir.path, exeFilename);
      // Directory moved successfully. New exe path
      return newExePath;
    } catch (e) {
      // Error moving directory
      throw Exception('Failed to move game folder: $e');
    }
  }

  /// Prepares the environment variables needed to run commands within a prefix.
  Future<Map<String, String>> _prepareEnvironment(WinePrefix prefix) async {
    String wineBinaryName = 'wine';
    String wineServerBinaryName = 'wineserver';
    String wineBuildPath = prefix.wineBuildPath;
    String wineBinSubDir = 'bin';

    // Find wine executable in the proper location
    String? winePath;
    String? wineServerPath;
    
    if (wineBuildPath.isNotEmpty) {
      if (prefix.type == PrefixType.proton) {
        // For Proton builds, check multiple possible locations
        List<String> possibleWinePaths = [
          path.join(wineBuildPath, 'bin', wineBinaryName),              // Kronek/Standard location
          path.join(wineBuildPath, 'files', 'bin', wineBinaryName),     // Proton-GE structure
          path.join(wineBuildPath, 'dist', 'bin', wineBinaryName),      // Alternative Proton structure
        ];
        
        List<String> possibleWineServerPaths = [
          path.join(wineBuildPath, 'bin', wineServerBinaryName),        // Kronek/Standard location
          path.join(wineBuildPath, 'files', 'bin', wineServerBinaryName), // Proton-GE structure
          path.join(wineBuildPath, 'dist', 'bin', wineServerBinaryName),  // Alternative Proton structure
        ];
        
        // Find the correct wine path
        for (var possiblePath in possibleWinePaths) {
          if (await File(possiblePath).exists()) {
            winePath = possiblePath;
            wineBinSubDir = path.dirname(possiblePath).replaceFirst(wineBuildPath, '').replaceFirst(RegExp(r'^/'), '');
            break;
          }
        }
        
        // Find the correct wineserver path
        for (var possiblePath in possibleWineServerPaths) {
          if (await File(possiblePath).exists()) {
            wineServerPath = possiblePath;
            break;
          }
        }
        
        if (winePath == null) {
          throw Exception('Wine executable not found in any expected location for ${prefix.name}');
        }
        
        // If wineserver not found, assume it's in the same directory as wine
        if (wineServerPath == null && winePath != null) {
          wineServerPath = path.join(path.dirname(winePath), wineServerBinaryName);
        }
        
      } else {
        // For non-Proton builds, use the standard location
        winePath = path.join(wineBuildPath, wineBinSubDir, wineBinaryName);
        wineServerPath = path.join(wineBuildPath, wineBinSubDir, wineServerBinaryName);
        
        // Check if wine executable exists
        if (!await File(winePath).exists()) {
          throw Exception('Wine executable not found at $winePath');
        }
      }
    } else if (prefix.type == PrefixType.custom) {
      // For custom prefixes, use system wine
      winePath = wineBinaryName;
      wineServerPath = wineServerBinaryName;
    }
    
    String wineBinDir = winePath != null ? path.dirname(winePath) : '';

    // Determine library directories based on the discovered wine binary location
    String wineLibDir = '';
    String wineLib64Dir = '';
    if (wineBuildPath.isNotEmpty) {
      // For Proton, base the lib paths on the discovered binary location
      if (prefix.type == PrefixType.proton) {
        if (wineBinDir.contains('files/bin')) {
          // Proton-GE structure
          wineLibDir = path.join(wineBuildPath, 'files', 'lib');
          wineLib64Dir = path.join(wineBuildPath, 'files', 'lib64');
        } else if (wineBinDir.contains('dist/bin')) {
          // Alternative Proton structure
          wineLibDir = path.join(wineBuildPath, 'dist', 'lib');
          wineLib64Dir = path.join(wineBuildPath, 'dist', 'lib64');
        } else {
          // Standard/Kronek structure
          wineLibDir = path.join(wineBuildPath, 'lib');
          wineLib64Dir = path.join(wineBuildPath, 'lib64');
        }
      } else {
        // Standard Wine structure
        wineLibDir = path.join(wineBuildPath, 'lib');
        wineLib64Dir = path.join(wineBuildPath, 'lib64');
      }
    }

    // Base environment variables
    final env = {
      ...Platform.environment,
      'WINEPREFIX': prefix.path,
      if (wineBuildPath.isNotEmpty && winePath != null) ...{
         'PATH': '$wineBinDir:${Platform.environment['PATH'] ?? ''}',
         'LD_LIBRARY_PATH': '$wineLib64Dir:$wineLibDir:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
         'WINE': winePath,
         'WINESERVER': wineServerPath ?? path.join(wineBinDir, wineServerBinaryName),
      },
      if (prefix.type == PrefixType.proton) ...{
        'STEAM_COMPAT_DATA_PATH': prefix.path,
        'STEAM_COMPAT_CLIENT_INSTALL_PATH': Platform.environment['HOME'] ?? '.',
        'SteamAppId': prefix.exeEntries.firstWhere((e) => e.steamAppId != null, orElse: () => const ExeEntry(path: '', name: '', steamAppId: 0)).steamAppId?.toString() ?? '0',
        'SteamGameId': prefix.exeEntries.firstWhere((e) => e.steamAppId != null, orElse: () => const ExeEntry(path: '', name: '', steamAppId: 0)).steamAppId?.toString() ?? '0',
        'STEAM_COMPAT_APP_ID': prefix.exeEntries.firstWhere((e) => e.steamAppId != null, orElse: () => const ExeEntry(path: '', name: '', steamAppId: 0)).steamAppId?.toString() ?? '0',
      },
      // Add user-defined environment variables stored in the prefix
      ...prefix.environmentVariables,
    };
    return env;
  }


  /// Launches winecfg for the specified prefix.
  Future<void> runWinecfg(WinePrefix prefix) async {
    try {
      final env = await _prepareEnvironment(prefix);
      final winePath = env['WINE'] ?? 'wine'; // Get wine path from env or default to 'wine'
      await Process.start(
        winePath,
        ['winecfg'],
        environment: env,
        runInShell: false,
      );
    } catch (e) {
      final errorMsg = 'Error launching winecfg process: $e';
      throw Exception(errorMsg);
    }
  }

  /// Launches the Winetricks GUI for the specified prefix.
  Future<void> runWinetricksGui(WinePrefix prefix) async {
    try {
      final env = await _prepareEnvironment(prefix);
      // Assume winetricks is in the system PATH
      await Process.start(
        'winetricks',
        ['--gui'],
        environment: env,
        runInShell: false,
      );
    } catch (e) {
      final errorMsg = 'Error launching Winetricks GUI: $e. Make sure winetricks is installed and in your PATH.';
      throw Exception(errorMsg);
    }
  }

  /// Launches Wine Explorer for the specified prefix.
  Future<void> runWineExplorer(WinePrefix prefix) async {
    try {
      final env = await _prepareEnvironment(prefix);
      final winePath = env['WINE'] ?? 'wine';
      await Process.start(
        winePath,
        ['explorer'],
        environment: env,
        runInShell: false,
      );
    } catch (e) {
      final errorMsg = 'Error launching Wine Explorer: $e';
      throw Exception(errorMsg);
    }
  }

  /// Applies controller fixes to the prefix by adding registry entries
  /// for better controller support.
  Future<void> applyControllerFix(WinePrefix prefix) async {
    try {
      _logService.log('Applying controller fixes to prefix: ${prefix.name}');
      final env = await _prepareEnvironment(prefix);
      final winePath = env['WINE'] ?? 'wine';
      
      // First registry entry: DisableHidraw
      final disableHidrawResult = await Process.run(
        winePath,
        ['reg', 'add', 'HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\winebus', 
              '/v', 'DisableHidraw', '/t', 'REG_DWORD', '/d', '1', '/f'],
        environment: env,
      );
      
      if (disableHidrawResult.exitCode != 0) {
        _logService.log('Error adding DisableHidraw registry entry: ${disableHidrawResult.stderr}', LogLevel.error);
        throw Exception('Failed to add DisableHidraw registry entry: ${disableHidrawResult.stderr}');
      }
      
      // Second registry entry: Enable SDL
      final enableSDLResult = await Process.run(
        winePath,
        ['reg', 'add', 'HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\winebus', 
              '/v', 'Enable SDL', '/t', 'REG_DWORD', '/d', '1', '/f'],
        environment: env,
      );
      
      if (enableSDLResult.exitCode != 0) {
        _logService.log('Error adding Enable SDL registry entry: ${enableSDLResult.stderr}', LogLevel.error);
        throw Exception('Failed to add Enable SDL registry entry: ${enableSDLResult.stderr}');
      }
      
      _logService.log('Controller fixes successfully applied to prefix: ${prefix.name}');
    } catch (e) {
      _logService.log('Error applying controller fixes: $e', LogLevel.error);
      throw Exception('Error applying controller fixes: $e');
    }
  }

  /// Determines if a prefix has DXVK and VKD3D-Proton properly installed
  Future<Map<String, bool>> checkDirectXSupportComponents(WinePrefix prefix) async {
    try {
      _logService.log('Checking DirectX support components for prefix: ${prefix.name}');
      final env = await _prepareEnvironment(prefix);
      
      final result = {
        'dxvk': false,
        'vkd3d': false
      };
      
      // Check for DXVK files (d3d9.dll, d3d11.dll, etc.)
      final dxvkFiles = ['d3d9.dll', 'd3d11.dll', 'dxgi.dll'];
      var dxvkDetected = false;
      
      // Get a list of all possible paths to check for DLL files
      List<String> dllPaths = [];
      
      // Standard locations
      dllPaths.add(path.join(prefix.path, 'drive_c', 'windows', 'system32'));
      dllPaths.add(path.join(prefix.path, 'drive_c', 'windows', 'syswow64'));
      
      // Proton pfx structure
      dllPaths.add(path.join(prefix.path, 'pfx', 'drive_c', 'windows', 'system32'));
      dllPaths.add(path.join(prefix.path, 'pfx', 'drive_c', 'windows', 'syswow64'));
      
      // Log the paths we're checking
      _logService.log('Checking for DLLs in paths: ${dllPaths.join(', ')}');
      
      // Check for DXVK files
      for (final dllPath in dllPaths) {
        if (dxvkDetected) break;  // If already detected, no need to check more
        
        for (final dllFile in dxvkFiles) {
          final fullPath = path.join(dllPath, dllFile);
          if (await File(fullPath).exists()) {
            dxvkDetected = true;
            _logService.log('Found DXVK component: $fullPath');
            break;
          }
        }
      }
      
      // Check for VKD3D files (d3d12.dll)
      final vkd3dFiles = ['d3d12.dll'];
      var vkd3dDetected = false;
      
      for (final dllPath in dllPaths) {
        if (vkd3dDetected) break;  // If already detected, no need to check more
        
        for (final dllFile in vkd3dFiles) {
          final fullPath = path.join(dllPath, dllFile);
          if (await File(fullPath).exists()) {
            vkd3dDetected = true;
            _logService.log('Found VKD3D component: $fullPath');
            break;
          }
        }
      }
      
      // If Proton-GE (not Kronek), assume components are present
      if (prefix.type == PrefixType.proton && 
          !prefix.wineBuildPath.contains('wine-proton') && 
          !prefix.wineBuildPath.contains('Kronek')) {
        // For Proton-GE, components are bundled
        _logService.log('Detected Proton-GE build, assuming DXVK and VKD3D are included');
        dxvkDetected = true;
        vkd3dDetected = true;
      }
      
      // If wine is in a non-standard path, try to validate by running wine --version
      if ((!dxvkDetected || !vkd3dDetected) && prefix.type == PrefixType.proton) {
        try {
          final winePath = env['WINE'] ?? 'wine';
          final result = await Process.run(
            winePath, ['--version'], 
            environment: env
          );
          
          // Check if this is Proton output
          if (result.stdout.toString().toLowerCase().contains('proton')) {
            _logService.log('Validated as Proton: ${result.stdout}');
            // For Proton builds, often the DLLs are integrated but not directly visible
            // If Kronek Proton, only assume DXVK is present but not VKD3D
            if (prefix.wineBuildPath.contains('wine-proton') || 
                prefix.wineBuildPath.contains('Kronek')) {
              dxvkDetected = true;
              // Don't assume VKD3D is present in Kronek Proton
            } else {
              // For other Proton builds, assume both
              dxvkDetected = true;
              vkd3dDetected = true;
            }
          }
        } catch (e) {
          _logService.log('Error validating with wine --version: $e', LogLevel.warning);
        }
      }
      
      // Set the results
      result['dxvk'] = dxvkDetected;
      result['vkd3d'] = vkd3dDetected;
      
      _logService.log('DirectX support check for "${prefix.name}": DXVK: ${dxvkDetected ? 'Found' : 'Not Found'}, VKD3D: ${vkd3dDetected ? 'Found' : 'Not Found'}');
      return result;
    } catch (e) {
      _logService.log('Error checking DirectX support components: $e', LogLevel.error);
      return {'dxvk': false, 'vkd3d': false};
    }
  }

  /// Installs VKD3D-Proton to a Kronek Proton prefix
  Future<bool> installVkd3dToProtonPrefix(WinePrefix prefix, {Function(String)? progressCallback}) async {
    if (prefix.type != PrefixType.proton) {
      progressCallback?.call('This method is only for Proton prefixes.');
      return false;
    }
    
    try {
      progressCallback?.call('Installing VKD3D-Proton to Kronek Proton prefix: ${prefix.name}');
      final env = await _prepareEnvironment(prefix);
      final winePath = env['WINE'] ?? 'wine';
      
      // Download the latest version of VKD3D from GitHub
      const specificVersion = 'v2.14.1';
      const specificVersionNumber = '2.14.1';
      const directUrl = 'https://github.com/HansKristian-Work/vkd3d-proton/releases/download/$specificVersion/vkd3d-proton-$specificVersionNumber.tar.zst';
      
      progressCallback?.call('Downloading VKD3D-Proton $specificVersionNumber...');
      final tempDir = Directory.systemTemp.createTempSync('vkd3d_download_');
      final downloadPath = path.join(tempDir.path, 'vkd3d-proton.tar.zst');
      
      // Perform download
      final request = http.Request('GET', Uri.parse(directUrl));
      final response = await http.Client().send(request);
      
      if (response.statusCode != 200) {
        progressCallback?.call('Failed to download VKD3D-Proton: HTTP ${response.statusCode}');
        return false;
      }
      
      final file = File(downloadPath);
      await response.stream.pipe(file.openWrite());
      progressCallback?.call('Download complete: ${downloadPath}');
      
      // Extract using zstd and tar
      progressCallback?.call('Extracting VKD3D-Proton...');
      final extractDir = Directory.systemTemp.createTempSync('vkd3d_extract_');
      
      // Check if zstd is installed
      final zstdResult = await Process.run('which', ['zstd']);
      if (zstdResult.exitCode != 0) {
        progressCallback?.call('Error: zstd not found. Please install zstd.');
        return false;
      }
      
      // Extract using zstd
      final tarFile = path.join(tempDir.path, 'vkd3d-proton.tar');
      final zstdExtractResult = await Process.run('zstd', ['-d', downloadPath, '-o', tarFile]);
      if (zstdExtractResult.exitCode != 0) {
        progressCallback?.call('Error extracting with zstd: ${zstdExtractResult.stderr}');
        return false;
      }
      
      // Extract tar file
      final tarExtractResult = await Process.run('tar', ['-xf', tarFile, '-C', extractDir.path]);
      if (tarExtractResult.exitCode != 0) {
        progressCallback?.call('Error extracting tar: ${tarExtractResult.stderr}');
        return false;
      }
      
      // Find the setup script
      progressCallback?.call('Looking for setup_vkd3d_proton.sh...');
      File? setupScript;
      
      void findSetupScript(Directory dir) {
        for (var entity in dir.listSync()) {
          if (entity is File && path.basename(entity.path) == 'setup_vkd3d_proton.sh') {
            setupScript = entity;
            return;
          } else if (entity is Directory) {
            findSetupScript(entity);
            if (setupScript != null) return;
          }
        }
      }
      
      findSetupScript(extractDir);
      
      if (setupScript == null) {
        progressCallback?.call('Could not find setup_vkd3d_proton.sh in the extracted files.');
        return false;
      }
      
      // Make setup script executable
      await Process.run('chmod', ['+x', setupScript!.path]);
      
      // Run the script with the WINEPREFIX set
      progressCallback?.call('Installing VKD3D-Proton to prefix: ${prefix.path}');
      final installResult = await Process.run(
        'bash',
        [setupScript!.path, 'install'],
        environment: env,
        workingDirectory: path.dirname(setupScript!.path)
      );
      
      if (installResult.exitCode != 0) {
        progressCallback?.call('VKD3D-Proton installation failed: ${installResult.stderr}');
        return false;
      }
      
      progressCallback?.call('VKD3D-Proton installation successful!');
      _logService.log('Successfully installed VKD3D-Proton to Kronek Proton prefix: ${prefix.name}');
      return true;
      
    } catch (e) {
      progressCallback?.call('Error installing VKD3D-Proton: $e');
      _logService.log('Error installing VKD3D-Proton to Kronek Proton prefix: $e', LogLevel.error);
      return false;
    }
  }

  /// Installs both DXVK and VKD3D-Proton to ensure complete DirectX 9-12 compatibility
  Future<bool> installCompleteDirectXSupport(WinePrefix prefix, Settings settings, {Function(String)? progressCallback}) async {
    try {
      _logService.log('Installing complete DirectX support for prefix: ${prefix.name}');
      progressCallback?.call('Starting combined DXVK and VKD3D installation...');
      
      // Create an instance of the component installer
      final installer = WineComponentInstaller();
      bool dxvkSuccess = false;
      bool vkd3dSuccess = false;
      
      // Install DXVK first
      progressCallback?.call('Step 1/2: Installing DXVK...');
      if (prefix.type == PrefixType.proton) {
        if (prefix.wineBuildPath.contains('wine-proton') || prefix.wineBuildPath.contains('Kronek')) {
          // For Kronek Proton, use standard DXVK installation
          dxvkSuccess = await installer.installDxvk(prefix, settings, progressCallback: progressCallback);
        } else {
          // For Proton-GE, DXVK is already included
          progressCallback?.call('DXVK is already included in Proton-GE builds');
          dxvkSuccess = true;
        }
      } else {
        // Normal DXVK installation for Wine prefixes
        dxvkSuccess = await installer.installDxvk(prefix, settings, progressCallback: progressCallback);
      }
      
      if (!dxvkSuccess) {
        progressCallback?.call('DXVK installation failed, but continuing with VKD3D...');
        _logService.log('DXVK installation failed for ${prefix.name}', LogLevel.warning);
      }
      
      // Install VKD3D-Proton next
      progressCallback?.call('Step 2/2: Installing VKD3D-Proton (DirectX 12 support)...');
      if (prefix.type == PrefixType.proton) {
        if (prefix.wineBuildPath.contains('wine-proton') || prefix.wineBuildPath.contains('Kronek')) {
          // For Kronek Proton, use our specialized VKD3D installation
          vkd3dSuccess = await installVkd3dToProtonPrefix(prefix, progressCallback: progressCallback);
        } else {
          // For Proton-GE, VKD3D is already included
          progressCallback?.call('VKD3D-Proton is already included in Proton-GE builds');
          vkd3dSuccess = true;
        }
      } else {
        // Normal VKD3D installation for Wine prefixes
        vkd3dSuccess = await installer.installVkd3d(prefix, settings, progressCallback: progressCallback);
      }
      
      // Report results
      if (dxvkSuccess && vkd3dSuccess) {
        _logService.log('Successfully installed complete DirectX support for ${prefix.name}');
        progressCallback?.call('Successfully installed complete DirectX support!');
        return true;
      } else if (dxvkSuccess) {
        _logService.log('Only DXVK installation succeeded for ${prefix.name}', LogLevel.warning);
        progressCallback?.call('Only DXVK was successfully installed. DirectX 12 support might be limited.');
        return false;
      } else if (vkd3dSuccess) {
        _logService.log('Only VKD3D installation succeeded for ${prefix.name}', LogLevel.warning);
        progressCallback?.call('Only VKD3D was successfully installed. DirectX 9-11 support might be limited.');
        return false;
      } else {
        _logService.log('Both DXVK and VKD3D installations failed for ${prefix.name}', LogLevel.error);
        progressCallback?.call('Failed to install both DXVK and VKD3D.');
        return false;
      }
      
    } catch (e) {
      _logService.log('Error installing DirectX support: $e', LogLevel.error);
      progressCallback?.call('Error installing DirectX support: $e');
      return false;
    }
  }

  // Removed Winetricks verb methods

}