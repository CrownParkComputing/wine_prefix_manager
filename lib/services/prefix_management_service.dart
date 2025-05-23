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
  Future<List<WinePrefix>> scanForPrefixes(Settings settings) async {
    final List<WinePrefix> prefixes = [];
    List<WinePrefix> invalidPrefixes = []; // Track invalid prefixes for cleanup

    // Determine the base directory for prefixes
    String baseDir;
    if (settings.prefixDirectory.isNotEmpty && Directory(settings.prefixDirectory).existsSync()) {
      baseDir = settings.prefixDirectory;
    } else {
      final homeDir = Platform.environment['HOME'];
      if (homeDir != null) {
        baseDir = path.join(homeDir, '.local', 'share', 'wineprefixes');
      } else {
        baseDir = path.join(Directory.current.absolute.path, 'wineprefixes');
      }
    }

    _logService.log('Scanning for prefixes in: $baseDir');

    if (!Directory(baseDir).existsSync()) {
      _logService.log('Base prefix directory does not exist: $baseDir');
      return prefixes; // Return empty list if directory doesn't exist
    }

    // Define expected type subdirectories
    final typeSubdirs = ['wine', 'proton', 'proton-ge', 'proton-kronek', 'custom'];

    for (final typeSubdir in typeSubdirs) {
      final typeDirPath = path.join(baseDir, typeSubdir);
      
      if (!Directory(typeDirPath).existsSync()) {
        _logService.log('Skipping non-existent subdirectory: $typeDirPath');
        continue;
      }

      _logService.log('Scanning subdirectory: $typeDirPath');
      await for (final entity in Directory(typeDirPath).list()) {
        if (entity is Directory) {
          _logService.log('Checking directory: ${entity.path}');
          try {
            final WinePrefix? prefix = await _processDirectory(entity.path, typeSubdir);
            if (prefix != null) {
              // Validate the prefix before adding
              final bool isValid = await _validatePrefix(prefix);
              if (isValid) {
                prefixes.add(prefix);
                _logService.log('Added prefix: ${prefix.name}, type: ${prefix.type.name}, arch: ${prefix.architecture}, path: ${prefix.path}');
              } else {
                invalidPrefixes.add(prefix);
                _logService.log('Found invalid prefix: ${prefix.name} at ${prefix.path}', LogLevel.warning);
              }
            }
          } catch (e) {
            _logService.log('Error processing directory ${entity.path}: $e', LogLevel.error);
          }
        }
      }
    }

    // Clean up invalid prefixes
    if (invalidPrefixes.isNotEmpty) {
      _logService.log('Found ${invalidPrefixes.length} invalid prefixes. Starting cleanup...');
      await _cleanupInvalidPrefixes(invalidPrefixes);
    }

    _logService.log('Scan complete. Found ${prefixes.length} valid prefixes.');
    return prefixes;
  }

  /// Validates a prefix to ensure it's usable
  Future<bool> _validatePrefix(WinePrefix prefix) async {
    try {
      // Check 1: Prefix directory must exist and contain essential Wine files
      if (!Directory(prefix.path).existsSync()) {
        _logService.log('Prefix directory does not exist: ${prefix.path}', LogLevel.warning);
        return false;
      }

      // Check for essential Wine files (system.reg, user.reg, or drive_c)
      final systemReg = File(path.join(prefix.path, 'system.reg'));
      final userReg = File(path.join(prefix.path, 'user.reg'));
      final driveC = Directory(path.join(prefix.path, 'drive_c'));
      
      if (!systemReg.existsSync() && !userReg.existsSync() && !driveC.existsSync()) {
        _logService.log('Prefix missing essential Wine files: ${prefix.path}', LogLevel.warning);
        return false;
      }

      // Check 2: Build path must exist (if specified)
      if (prefix.wineBuildPath.isNotEmpty) {
        if (!Directory(prefix.wineBuildPath).existsSync()) {
          _logService.log('Build path does not exist: ${prefix.wineBuildPath}', LogLevel.warning);
          return false;
        }

        // Check for essential executable based on prefix type
        String expectedExecutable;
        if (prefix.type == PrefixType.proton) {
          // For Proton, check for proton script
          expectedExecutable = path.join(prefix.wineBuildPath, 'proton');
          if (!File(expectedExecutable).existsSync()) {
            // Try proton.sh as alternative
            expectedExecutable = path.join(prefix.wineBuildPath, 'proton.sh');
            if (!File(expectedExecutable).existsSync()) {
              _logService.log('Proton script not found in build path: ${prefix.wineBuildPath}', LogLevel.warning);
              return false;
            }
          }
        } else {
          // For Wine, check for wine executable
          expectedExecutable = path.join(prefix.wineBuildPath, 'bin', 'wine');
          if (!File(expectedExecutable).existsSync()) {
            _logService.log('Wine executable not found in build path: ${expectedExecutable}', LogLevel.warning);
            return false;
          }
        }
      }

      // Check 3: Architecture must be valid
      if (prefix.architecture != 'win32' && prefix.architecture != 'win64') {
        _logService.log('Invalid architecture: ${prefix.architecture}', LogLevel.warning);
        return false;
      }

      return true;
    } catch (e) {
      _logService.log('Error validating prefix ${prefix.name}: $e', LogLevel.error);
      return false;
    }
  }

  /// Cleans up invalid prefixes
  Future<void> _cleanupInvalidPrefixes(List<WinePrefix> invalidPrefixes) async {
    for (final prefix in invalidPrefixes) {
      try {
        _logService.log('Cleaning up invalid prefix: ${prefix.name} at ${prefix.path}');
        
        // Remove the prefix directory and its contents
        final prefixDir = Directory(prefix.path);
        if (prefixDir.existsSync()) {
          await prefixDir.delete(recursive: true);
          _logService.log('Deleted invalid prefix directory: ${prefix.path}');
        }

        // Clean up empty parent directories
        await _cleanupEmptyParentDirectories(prefix.path);
        
      } catch (e) {
        _logService.log('Error cleaning up invalid prefix ${prefix.name}: $e', LogLevel.error);
      }
    }
    
    _logService.log('Cleanup complete. Removed ${invalidPrefixes.length} invalid prefixes.');
  }

  /// Removes empty parent directories up to the type subdirectory level
  Future<void> _cleanupEmptyParentDirectories(String prefixPath) async {
    try {
      final parentDir = Directory(path.dirname(prefixPath));
      
      // Only clean up if the parent is a type subdirectory (wine, proton, etc.)
      final parentName = path.basename(parentDir.path);
      final validTypeNames = ['wine', 'proton', 'proton-ge', 'proton-kronek', 'custom'];
      
      if (validTypeNames.contains(parentName) && parentDir.existsSync()) {
        // Check if directory is empty
        final contents = await parentDir.list().toList();
        if (contents.isEmpty) {
          await parentDir.delete();
          _logService.log('Removed empty type directory: ${parentDir.path}');
        }
      }
    } catch (e) {
      _logService.log('Error cleaning up empty parent directories for $prefixPath: $e', LogLevel.warning);
    }
  }

  Future<WinePrefix?> _processDirectory(String dirPath, String typeSubdir) async {
    final prefixName = path.basename(dirPath);
    
    // Check for registry files or drive_c directory
    final systemReg = File(path.join(dirPath, 'system.reg'));
    final userReg = File(path.join(dirPath, 'user.reg'));
    final driveC = Directory(path.join(dirPath, 'drive_c'));
    
    if (!systemReg.existsSync() && !userReg.existsSync() && !driveC.existsSync()) {
      _logService.log('Skipping directory (no system.reg, user.reg, or drive_c found): $dirPath', LogLevel.warning);
      return null;
    }

    // Read configuration
    final configFile = File(path.join(dirPath, '.prefix_config'));
    String? buildPath;
    PrefixType type = PrefixType.wine;
    String architecture = 'win64';

    if (configFile.existsSync()) {
      try {
        final configContent = await configFile.readAsString();
        _logService.log('Config file content: $configContent');
        final config = json.decode(configContent);
        buildPath = config['buildPath'] as String?;
        architecture = config['architecture'] as String? ?? 'win64';
        
        final typeString = config['type'] as String? ?? 'PrefixType.wine';
        if (typeString == 'PrefixType.proton') {
          type = PrefixType.proton;
        } else {
          type = PrefixType.wine;
        }
        
        _logService.log('Read from config - buildPath: $buildPath, type: $typeString, architecture: $architecture');
      } catch (e) {
        _logService.log('Error reading config file: $e', LogLevel.error);
        // Continue with defaults
      }
    } else {
      // Guess type based on subdirectory
      if (typeSubdir.contains('proton') || prefixName.toLowerCase().contains('proton')) {
        type = PrefixType.proton;
      } else {
        type = PrefixType.wine;
      }
      _logService.log('Config file not found. Guessed type: ${type.name}');
    }

    _logService.log('Determined prefix type: ${type.name}');

    return WinePrefix(
      name: prefixName,
      path: dirPath,
      wineBuildPath: buildPath ?? '',
      type: type,
      architecture: architecture,
      exeEntries: [],
    );
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
    } else if (prefix.type == PrefixType.wine) {
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

  /// Applies a common controller fix (XInput, DInput) to the prefix.
  /// This typically involves running a script or specific Winetricks verbs.
  Future<void> applyControllerFix(
    WinePrefix prefix,
    {Function(String)? onStatusUpdate,
     String? customWineExecutable,
     Map<String, String>? customEnv,}
  ) async {
    onStatusUpdate?.call('Applying winebus controller fix...');
    _logService.log('Applying winebus controller fix for prefix: ${prefix.name}');

    final String wineExec = customWineExecutable ?? await getWineExecutableForPrefix(prefix) ?? await _prepareEnvironment(prefix).then((env) => env['WINE'] ?? 'wine');
    final Map<String,String> env = customEnv ?? await _prepareEnvironment(prefix);
    
    final commandShell = Shell(environment: env, verbose: true);

    // Determine if this is a Proton executable (not a wine executable)
    final bool isProtonExecutable = wineExec.contains('proton') && !wineExec.endsWith('/wine') && !wineExec.endsWith('/wine64');

    final List<Map<String, String>> regCommands = [
      {
        'key': '"HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\winebus"',
        'valueName': '"DisableHidraw"',
        'type': 'REG_DWORD',
        'data': '1',
        'description': 'Disabling Hidraw for winebus'
      },
      {
        'key': '"HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\winebus"',
        'valueName': '"Enable SDL"',
        'type': 'REG_DWORD',
        'data': '1',
        'description': 'Enabling SDL for winebus'
      }
    ];

    for (final cmdDetails in regCommands) {
      String commandString;
      if (isProtonExecutable) {
        // For Proton executables, prefix with 'run'
        commandString = '''$wineExec run reg add ${cmdDetails['key']} /v ${cmdDetails['valueName']} /t ${cmdDetails['type']} /d ${cmdDetails['data']} /f''';
      } else {
        // For regular wine executables
        commandString = '''$wineExec reg add ${cmdDetails['key']} /v ${cmdDetails['valueName']} /t ${cmdDetails['type']} /d ${cmdDetails['data']} /f''';
      }
      
      onStatusUpdate?.call('Applying: ${cmdDetails['description']}');
      _logService.log('Executing registry command: $commandString');
      try {
        final result = await commandShell.run(commandString);
        if (result.first.exitCode == 0) {
          _logService.log('Successfully applied registry change: ${cmdDetails['valueName']}');
        } else {
          _logService.log('Failed to apply registry change: ${cmdDetails['valueName']}. Error: ${result.first.errText}', LogLevel.error);
          onStatusUpdate?.call('Failed to apply: ${cmdDetails['valueName']}');
        }
      } catch (e) {
        _logService.log('Exception during registry command for ${cmdDetails['valueName']}: $e', LogLevel.error);
        onStatusUpdate?.call('Error applying: ${cmdDetails['valueName']}');
      }
    }

    onStatusUpdate?.call('Controller fix application finished.');
    _logService.log('Controller fix application finished for prefix: ${prefix.name}');
  }

  /// Retrieves the appropriate wine executable path for a given prefix.
  Future<String?> getWineExecutableForPrefix(WinePrefix prefix) async {
    // Implementation of getWineExecutableForPrefix method
    // This is a placeholder and should be implemented based on your specific requirements
    return null; // Placeholder return, actual implementation needed
  }

  /// Retrieves the appropriate environment variables for a given prefix.
  Future<Map<String, String>> getEnvironmentForPrefix(WinePrefix prefix) async {
    // Implementation of getEnvironmentForPrefix method
    // This is a placeholder and should be implemented based on your specific requirements
    return {}; // Placeholder return, actual implementation needed
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