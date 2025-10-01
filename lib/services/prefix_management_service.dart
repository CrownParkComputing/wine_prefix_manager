import 'dart:convert';
import 'dart:io';
import 'dart:async'; // Added for Completer and Timer
import 'package:path/path.dart' as path;
import 'package:process_run/shell.dart'; // Import Shell
import '../models/settings.dart';
import '../models/prefix_models.dart';
import 'log_service.dart'; // Add log service import
import 'package:http/http.dart' as http;
import 'wine_component_installer.dart'; // Add import for WineComponentInstaller
import '../utils/path_utils.dart'; // Import the path utility
// Added for ProcessService
import '../utils/logger.dart';

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
      logError('Error initializing LogService', e);
    }
  }

  /// Scans the prefix directory specified in settings for existing Wine/Proton prefixes.
  /// Returns a list of discovered WinePrefix objects.
  Future<List<WinePrefix>> scanForPrefixes(Settings settings) async {
    final List<WinePrefix> prefixes = [];
    List<WinePrefix> invalidPrefixes = []; // Track invalid prefixes for cleanup
    final Set<String> processedPaths = {}; // Track processed paths to avoid duplicates

    String effectivePrefixBaseDir;
    // final homeDir = Platform.environment['HOME']; // No longer directly needed here for default path

    logDebug('[DEBUG] scanForPrefixes called with settings.prefixDirectory: ${settings.prefixDirectory}');

    // Priority 1: User-defined absolute path in settings
    if (settings.prefixDirectory.isNotEmpty && path.isAbsolute(settings.prefixDirectory)) {
      if (await Directory(settings.prefixDirectory).exists()) {
        effectivePrefixBaseDir = settings.prefixDirectory;
        logDebug('[DEBUG] Using user-defined directory: $effectivePrefixBaseDir');
        _logService.log('Scanning for prefixes in user-defined directory: $effectivePrefixBaseDir');
      } else {
        _logService.log('User-defined prefix directory "${settings.prefixDirectory}" does not exist. Falling back to default.', LogLevel.warning);
        // Fallback to default if user-defined path is invalid
        final baseAppDataPath = await getBaseAppDataPath();
        effectivePrefixBaseDir = path.join(baseAppDataPath, 'prefixes');
        logDebug('[DEBUG] Fallback to default: $effectivePrefixBaseDir');
        _logService.log('Using default scan path: $effectivePrefixBaseDir due to invalid user setting.');
      }
    } else {
      // Priority 2: Default path
      if (settings.prefixDirectory.isNotEmpty) {
        // Log if it was set but not absolute (or empty and thus handled by default pathing in settings load)
         _logService.log('Settings.prefixDirectory ("${settings.prefixDirectory}") is not absolute or was empty. Using default scan path.', LogLevel.warning);
      }
      final baseAppDataPath = await getBaseAppDataPath();
      effectivePrefixBaseDir = path.join(baseAppDataPath, 'prefixes');
      logDebug('[DEBUG] Using default directory: $effectivePrefixBaseDir');
      _logService.log('Scanning for prefixes in default directory: $effectivePrefixBaseDir');
    }

    logDebug('[DEBUG] Final effectivePrefixBaseDir: $effectivePrefixBaseDir');
    logDebug('[DEBUG] Directory exists: ${await Directory(effectivePrefixBaseDir).exists()}');

    if (!await Directory(effectivePrefixBaseDir).exists()) {
      _logService.log('Base prefix directory for scanning does not exist: $effectivePrefixBaseDir');
      try {
        // Attempt to create it if it doesn't exist (useful for first run or if user deleted it)
        await Directory(effectivePrefixBaseDir).create(recursive: true);
        _logService.log('Created base prefix directory: $effectivePrefixBaseDir');
      } catch (e) {
        _logService.log('Failed to create base prefix directory $effectivePrefixBaseDir: $e', LogLevel.warning);
        return prefixes; // Return empty list if directory creation fails
      }
    }

    // First, check for the default Wine prefix at ~/.wine
    await _scanDefaultWinePrefix(prefixes, invalidPrefixes);

    // Define expected type subdirectories
    final typeSubdirs = ['wine', 'proton', 'proton-ge', 'proton-kronek', 'custom'];

    for (final typeSubdir in typeSubdirs) {
      final typeDirPath = path.join(effectivePrefixBaseDir, typeSubdir);
      logDebug('[DEBUG] Checking type subdirectory: $typeDirPath');
      
      if (!Directory(typeDirPath).existsSync()) {
        logDebug('[DEBUG] Subdirectory does not exist: $typeDirPath');
        _logService.log('Skipping non-existent subdirectory: $typeDirPath');
        continue;
      }

      logDebug('[DEBUG] Scanning subdirectory: $typeDirPath');
      _logService.log('Scanning subdirectory: $typeDirPath');
      
      // Get all directories in this type subdirectory
      final directories = <Directory>[];
      await for (final entity in Directory(typeDirPath).list()) {
        if (entity is Directory) {
          directories.add(entity);
        }
      }
      
      // Process directories, but check for pfx relationships first
      for (final directory in directories) {
        final dirPath = directory.path;
        
        // Skip if we've already processed this path
        if (processedPaths.contains(dirPath)) {
          logDebug('[DEBUG] Already processed: $dirPath');
          continue;
        }
        
        logDebug('[DEBUG] Found directory: $dirPath');
        _logService.log('Checking directory: $dirPath');
        
        // Check if this directory has a pfx subdirectory with Wine files
        final pfxDir = path.join(dirPath, 'pfx');
        final pfxSystemReg = File(path.join(pfxDir, 'system.reg'));
        final pfxUserReg = File(path.join(pfxDir, 'user.reg'));
        final pfxDriveC = Directory(path.join(pfxDir, 'drive_c'));
        final hasPfxWineFiles = pfxSystemReg.existsSync() || pfxUserReg.existsSync() || pfxDriveC.existsSync();
        
        // If this directory has a pfx subdirectory with Wine files, 
        // mark both the parent and pfx paths as processed and only process the parent
        if (hasPfxWineFiles && Directory(pfxDir).existsSync()) {
          logDebug('[DEBUG] Found Proton prefix structure: $dirPath with pfx subdirectory');
          _logService.log('Found Proton prefix structure with pfx subdirectory: $dirPath');
          
          // Mark both paths as processed to avoid duplicate detection
          processedPaths.add(dirPath);
          processedPaths.add(pfxDir);
          
          // Process the parent directory (it will internally use the pfx path for the actual prefix)
          try {
            final WinePrefix? prefix = await _processDirectory(dirPath, typeSubdir);
            logDebug('[DEBUG] _processDirectory returned: ${prefix?.name ?? 'null'}');
            if (prefix != null) {
              // Validate the prefix before adding
              final bool isValid = await _validatePrefix(prefix);
              logDebug('[DEBUG] Prefix validation result: $isValid for ${prefix.name}');
              if (isValid) {
                prefixes.add(prefix);
                logDebug('[DEBUG] Added valid prefix: ${prefix.name}');
                _logService.log('Added prefix: ${prefix.name}, type: ${prefix.type.name}, arch: ${prefix.architecture}, path: ${prefix.path}');
              } else {
                invalidPrefixes.add(prefix);
                logDebug('[DEBUG] Prefix marked as invalid: ${prefix.name}');
                _logService.log('Found invalid prefix: ${prefix.name} at ${prefix.path}', LogLevel.warning);
              }
            }
          } catch (e) {
            logDebug('[DEBUG] Error processing directory $dirPath: $e');
            _logService.log('Error processing directory $dirPath: $e', LogLevel.error);
          }
        } else {
          // Regular directory processing for non-Proton or direct Wine prefixes
          processedPaths.add(dirPath);
          
          try {
            final WinePrefix? prefix = await _processDirectory(dirPath, typeSubdir);
            logDebug('[DEBUG] _processDirectory returned: ${prefix?.name ?? 'null'}');
            if (prefix != null) {
              // Validate the prefix before adding
              final bool isValid = await _validatePrefix(prefix);
              logDebug('[DEBUG] Prefix validation result: $isValid for ${prefix.name}');
              if (isValid) {
                prefixes.add(prefix);
                logDebug('[DEBUG] Added valid prefix: ${prefix.name}');
                _logService.log('Added prefix: ${prefix.name}, type: ${prefix.type.name}, arch: ${prefix.architecture}, path: ${prefix.path}');
              } else {
                invalidPrefixes.add(prefix);
                logDebug('[DEBUG] Prefix marked as invalid: ${prefix.name}');
                _logService.log('Found invalid prefix: ${prefix.name} at ${prefix.path}', LogLevel.warning);
              }
            }
          } catch (e) {
            logDebug('[DEBUG] Error processing directory $dirPath: $e');
            _logService.log('Error processing directory $dirPath: $e', LogLevel.error);
          }
        }
      }
    }

    // Clean up invalid prefixes
    if (invalidPrefixes.isNotEmpty) {
      _logService.log('Found ${invalidPrefixes.length} invalid prefixes. Starting cleanup...');
      await _cleanupInvalidPrefixes(invalidPrefixes);
    }

    logDebug('[DEBUG] Scan complete. Found ${prefixes.length} valid prefixes.');
    _logService.log('Scan complete. Found ${prefixes.length} valid prefixes.');
    return prefixes;
  }

  /// Scans for the default Wine prefix at ~/.wine
  Future<void> _scanDefaultWinePrefix(List<WinePrefix> prefixes, List<WinePrefix> invalidPrefixes) async {
    try {
      final homeDir = Platform.environment['HOME'];
      if (homeDir == null || homeDir.isEmpty) {
        logDebug('[DEBUG] HOME environment variable not found, skipping default Wine prefix scan');
        _logService.log('HOME environment variable not found, skipping default Wine prefix scan', LogLevel.warning);
        return;
      }

      final defaultWinePrefixPath = path.join(homeDir, '.wine');
      logDebug('[DEBUG] Checking for default Wine prefix at: $defaultWinePrefixPath');
      _logService.log('Checking for default Wine prefix at: $defaultWinePrefixPath');

      if (!Directory(defaultWinePrefixPath).existsSync()) {
        logDebug('[DEBUG] Default Wine prefix not found at: $defaultWinePrefixPath');
        _logService.log('Default Wine prefix not found at: $defaultWinePrefixPath');
        return;
      }

      logDebug('[DEBUG] Found default Wine prefix directory: $defaultWinePrefixPath');
      _logService.log('Found default Wine prefix directory: $defaultWinePrefixPath');

      // Check if this prefix is already in our managed prefixes (avoid duplicates)
      final alreadyExists = prefixes.any((p) => p.path == defaultWinePrefixPath);
      if (alreadyExists) {
        logDebug('[DEBUG] Default Wine prefix already exists in managed prefixes, skipping');
        _logService.log('Default Wine prefix already exists in managed prefixes, skipping');
        return;
      }

      // Process the default Wine prefix
      final WinePrefix? defaultPrefix = await _processDirectory(defaultWinePrefixPath, 'wine');
      if (defaultPrefix != null) {
        // Create a special version with a clear name indicating it's the default prefix
        final namedDefaultPrefix = defaultPrefix.copyWith(
          name: 'default-wine-prefix',
        );
        
        logDebug('[DEBUG] Processed default Wine prefix: ${namedDefaultPrefix.name}');
        
        // Validate the prefix before adding
        final bool isValid = await _validatePrefix(namedDefaultPrefix);
        logDebug('[DEBUG] Default Wine prefix validation result: $isValid');
        
        if (isValid) {
          prefixes.add(namedDefaultPrefix);
          logDebug('[DEBUG] Added valid default Wine prefix: ${namedDefaultPrefix.name}');
          _logService.log('Added default Wine prefix: ${namedDefaultPrefix.name}, type: ${namedDefaultPrefix.type.name}, arch: ${namedDefaultPrefix.architecture}, path: ${namedDefaultPrefix.path}');
        } else {
          invalidPrefixes.add(namedDefaultPrefix);
          logDebug('[DEBUG] Default Wine prefix marked as invalid: ${namedDefaultPrefix.name}');
          _logService.log('Found invalid default Wine prefix: ${namedDefaultPrefix.name} at ${namedDefaultPrefix.path}', LogLevel.warning);
        }
      } else {
        logDebug('[DEBUG] Failed to process default Wine prefix directory');
        _logService.log('Failed to process default Wine prefix directory: $defaultWinePrefixPath', LogLevel.warning);
      }
    } catch (e) {
      logDebug('[DEBUG] Error scanning default Wine prefix: $e');
      _logService.log('Error scanning default Wine prefix: $e', LogLevel.error);
    }
  }

  /// Validates a prefix to ensure it's usable
  Future<bool> _validatePrefix(WinePrefix prefix) async {
    try {
      logDebug('[DEBUG] Validating prefix: ${prefix.name} at ${prefix.path}');
      
      // Check 1: Prefix directory must exist and contain essential Wine files
      if (!Directory(prefix.path).existsSync()) {
        logDebug('[DEBUG] Validation failed: Prefix directory does not exist: ${prefix.path}');
        _logService.log('Prefix directory does not exist: ${prefix.path}', LogLevel.warning);
        return false;
      }

      // Check for essential Wine files (system.reg, user.reg, or drive_c)
      final systemReg = File(path.join(prefix.path, 'system.reg'));
      final userReg = File(path.join(prefix.path, 'user.reg'));
      final driveC = Directory(path.join(prefix.path, 'drive_c'));
      
      _logService.log('Essential files check:');
    _logService.log('Checking files - system.reg: ${systemReg.existsSync()}, user.reg: ${userReg.existsSync()}, drive_c: ${driveC.existsSync()}');
      
      if (!systemReg.existsSync() && !userReg.existsSync() && !driveC.existsSync()) {
        logDebug('[DEBUG] Validation failed: Prefix missing essential Wine files: ${prefix.path}');
        _logService.log('Prefix missing essential Wine files: ${prefix.path}', LogLevel.warning);
        return false;
      }

      // Check 2: Build path must exist (if specified)
      if (prefix.wineBuildPath.isNotEmpty) {
        logDebug('[DEBUG] Checking build path: ${prefix.wineBuildPath}');
        if (!Directory(prefix.wineBuildPath).existsSync()) {
          logDebug('[DEBUG] Validation failed: Build path does not exist: ${prefix.wineBuildPath}');
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
              logDebug('[DEBUG] Validation failed: Proton script not found in build path: ${prefix.wineBuildPath}');
              _logService.log('Proton script not found in build path: ${prefix.wineBuildPath}', LogLevel.warning);
              return false;
            }
          }
        } else {
          // For Wine, check for wine executable
          expectedExecutable = path.join(prefix.wineBuildPath, 'bin', 'wine');
          logDebug('[DEBUG] Checking for wine executable: $expectedExecutable');
          if (!File(expectedExecutable).existsSync()) {
            logDebug('[DEBUG] Validation failed: Wine executable not found in build path: $expectedExecutable');
            _logService.log('Wine executable not found in build path: $expectedExecutable', LogLevel.warning);
            return false;
          }
          logDebug('[DEBUG] Wine executable found: $expectedExecutable');
        }
      } else if (prefix.type == PrefixType.wine) {
        // For Wine prefixes without a build path (like default ~/.wine), check if system Wine is available
        logDebug('[DEBUG] No build path specified, checking for system Wine availability');
        try {
          final result = await Process.run('which', ['wine']);
          if (result.exitCode == 0) {
            logDebug('[DEBUG] System Wine found: ${result.stdout.toString().trim()}');
            _logService.log('System Wine found for prefix ${prefix.name}: ${result.stdout.toString().trim()}');
          } else {
            logDebug('[DEBUG] Validation failed: System Wine not found and no build path specified');
            _logService.log('System Wine not found and no build path specified for prefix: ${prefix.name}', LogLevel.warning);
            return false;
          }
        } catch (e) {
          logDebug('[DEBUG] Error checking for system Wine: $e');
          _logService.log('Error checking for system Wine for prefix ${prefix.name}: $e', LogLevel.warning);
          return false;
        }
      }

      // Check 3: Architecture must be valid
      logDebug('[DEBUG] Checking architecture: ${prefix.architecture}');
      if (prefix.architecture != 'win32' && prefix.architecture != 'win64') {
        logDebug('[DEBUG] Validation failed: Invalid architecture: ${prefix.architecture}');
        _logService.log('Invalid architecture: ${prefix.architecture}', LogLevel.warning);
        return false;
      }

      logDebug('[DEBUG] Validation passed for prefix: ${prefix.name}');
      return true;
    } catch (e) {
      logDebug('[DEBUG] Validation error for prefix ${prefix.name}: $e');
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
    
    // Check for registry files or drive_c directory in main directory first
    final systemReg = File(path.join(dirPath, 'system.reg'));
    final userReg = File(path.join(dirPath, 'user.reg'));
    final driveC = Directory(path.join(dirPath, 'drive_c'));
    
    // Also check in pfx subdirectory (for Proton prefixes)
    final pfxDir = path.join(dirPath, 'pfx');
    final pfxSystemReg = File(path.join(pfxDir, 'system.reg'));
    final pfxUserReg = File(path.join(pfxDir, 'user.reg'));
    final pfxDriveC = Directory(path.join(pfxDir, 'drive_c'));
    
    // Check if Wine files exist in either location
    final hasMainWineFiles = systemReg.existsSync() || userReg.existsSync() || driveC.existsSync();
    final hasPfxWineFiles = pfxSystemReg.existsSync() || pfxUserReg.existsSync() || pfxDriveC.existsSync();
    
    if (!hasMainWineFiles && !hasPfxWineFiles) {
      _logService.log('Skipping directory (no system.reg, user.reg, or drive_c found): $dirPath', LogLevel.warning);
      return null;
    }

    // Determine the actual prefix path (use pfx subdirectory if that's where the Wine files are)
    String actualPrefixPath = dirPath;
    if (!hasMainWineFiles && hasPfxWineFiles) {
      actualPrefixPath = pfxDir;
      _logService.log('Using pfx subdirectory for Proton prefix: $actualPrefixPath');
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

    // Create the prefix object with the actual path where Wine files are located
    final prefix = WinePrefix(
      name: prefixName,
      path: actualPrefixPath, // Use the path where Wine files actually exist
      wineBuildPath: buildPath ?? '',
      type: type,
      architecture: architecture,
      exeEntries: [], // Will be loaded separately
      environmentVariables: {},
    );

    logDebug('[DEBUG] _processDirectory returned: $prefixName');
    return prefix;
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
        wineServerPath ??= path.join(path.dirname(winePath), wineServerBinaryName);
        
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
  Future<bool> applyControllerFix(
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
    return true; // Return success
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

  /// Checks for various installed components in a Wine prefix
  Future<Map<String, dynamic>> checkInstalledComponents(WinePrefix prefix) async {
    try {
      _logService.log('Checking installed components for prefix: ${prefix.name}');
      final env = await _prepareEnvironment(prefix);
      
      final result = {
        'dxvk': false,
        'vkd3d': false,
        'vcrun2019': false,
        'vcrun2022': false,
        'vcredist_x64': false,
        'vcredist_x86': false,
        'vcredist_legacy': false,
        'winetricks_list': <String>[],
      };
      
      // Check DirectX components (existing logic)
      final directXComponents = await checkDirectXSupportComponents(prefix);
      result['dxvk'] = directXComponents['dxvk'] ?? false;
      result['vkd3d'] = directXComponents['vkd3d'] ?? false;
      
      // Check VC++ redistributables via registry
      final vcppStatus = await _checkVcppRedistributablesRegistry(prefix, env);
      result.addAll(vcppStatus);
      
      // Check winetricks installed components
      final winetricksComponents = await _checkWinetricksInstalledComponents(prefix, env);
      result['winetricks_list'] = winetricksComponents;
      
      // Check specific winetricks VC++ runtimes
      result['vcrun2019'] = winetricksComponents.contains('vcrun2019');
      result['vcrun2022'] = winetricksComponents.contains('vcrun2022');
      
      _logService.log('Component check completed for "${prefix.name}"');
      return result;
    } catch (e) {
      _logService.log('Error checking installed components: $e', LogLevel.error);
      return {
        'dxvk': false,
        'vkd3d': false,
        'vcrun2019': false,
        'vcrun2022': false,
        'vcredist_x64': false,
        'vcredist_x86': false,
        'vcredist_legacy': false,
        'winetricks_list': <String>[],
      };
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
      progressCallback?.call('Download complete: $downloadPath');
      
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

  /// Diagnoses common issues with 32-bit Wine prefixes
  Future<Map<String, dynamic>> diagnose32BitPrefix(WinePrefix prefix) async {
    _logService.log("Starting 32-bit prefix diagnostics for ${prefix.name}");
    
    final results = <String, dynamic>{
      'prefix': prefix.name,
      'architecture': prefix.architecture,
      'issues': <String>[],
      'recommendations': <String>[],
      'details': <Map<String, dynamic>>[],
      'status': 'unknown',
    };
    
    try {
      // 1. Check if it's actually a 32-bit prefix
      if (prefix.architecture != 'win32') {
        results['issues'].add('This is not a 32-bit prefix (architecture: ${prefix.architecture})');
        results['recommendations'].add('Create a new 32-bit prefix with WINEARCH=win32');
        results['status'] = 'error';
        return results;
      }
      
      // 2. Check if registry files exist and are valid
      final systemRegistryFile = File(path.join(prefix.path, 'system.reg'));
      final userRegistryFile = File(path.join(prefix.path, 'user.reg'));
      final userdataDrive = Directory(path.join(prefix.path, 'drive_c'));
      
      if (!await systemRegistryFile.exists()) {
        results['issues'].add('Missing system.reg file');
        results['recommendations'].add('Repair or recreate the prefix');
        results['status'] = 'error';
      }
      
      if (!await userRegistryFile.exists()) {
        results['issues'].add('Missing user.reg file');
        results['recommendations'].add('Repair or recreate the prefix');
        results['status'] = 'error';
      }
      
      if (!await userdataDrive.exists()) {
        results['issues'].add('Missing drive_c directory');
        results['recommendations'].add('Repair or recreate the prefix');
        results['status'] = 'error';
      }
      
      // 3. Check if wineserver is running
      final wineServerRunning = await _isWineServerRunning(prefix.path);
      results['details'].add({
        'test': 'wineserver running',
        'result': wineServerRunning,
        'description': wineServerRunning ? 'WineServer is running (may interfere with operations)' : 'WineServer not running'
      });
      
      if (wineServerRunning) {
        results['issues'].add('WineServer is currently running for this prefix');
        results['recommendations'].add('Stop any Wine processes before performing operations');
      }
      
      // 4. Check Wine version for the prefix
      final wineVersion = await _getWineVersion(prefix);
      results['details'].add({
        'test': 'wine version',
        'result': wineVersion,
        'description': 'Detected Wine version: $wineVersion'
      });
      
      // 5. Test basic Wine functionality
      final canRunWine = await _testWineCommand(prefix);
      results['details'].add({
        'test': 'wine command',
        'result': canRunWine,
        'description': canRunWine ? 'Basic Wine command works' : 'Cannot run basic Wine command'
      });
      
      if (!canRunWine) {
        results['issues'].add('Cannot run basic Wine commands');
        results['recommendations'].add('Check Wine installation and path configuration');
        results['status'] = 'error';
      }
      
      // 6. Test winecfg specifically
      final canRunWinecfg = await _testWinecfg(prefix);
      results['details'].add({
        'test': 'winecfg',
        'result': canRunWinecfg,
        'description': canRunWinecfg ? 'winecfg runs successfully' : 'Cannot run winecfg'
      });
      
      if (!canRunWinecfg) {
        results['issues'].add('Cannot run winecfg');
        results['recommendations'].add('Try repairing the prefix');
      }
      
      // Set overall status if not already set
      if (results['status'] == 'unknown') {
        if (results['issues'].isEmpty) {
          results['status'] = 'ok';
          results['recommendations'].add('No issues detected. Prefix appears to be healthy.');
        } else {
          results['status'] = 'warning';
        }
      }
      
      _logService.log("32-bit prefix diagnostics complete: ${results['status']}");
      return results;
    } catch (e) {
      _logService.log("Error during 32-bit prefix diagnostics: $e", LogLevel.error);
      results['issues'].add('Error during diagnosis: $e');
      results['status'] = 'error';
      return results;
    }
  }
  
  /// Helper method to get Wine version for a prefix
  Future<String> _getWineVersion(WinePrefix prefix) async {
    try {
      final env = await _prepareEnvironment(prefix);
      final result = await Process.run('wine', ['--version'], environment: env);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
      return 'Unknown (error getting version)';
    } catch (e) {
      return 'Unknown (error: $e)';
    }
  }
  
  /// Helper method to test if Wine can run a basic command
  Future<bool> _testWineCommand(WinePrefix prefix) async {
    try {
      final env = await _prepareEnvironment(prefix);
      final result = await Process.run('wine', ['cmd', '/c', 'echo', 'test'], environment: env);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }
  
  /// Helper method to test if winecfg runs
  Future<bool> _testWinecfg(WinePrefix prefix) async {
    try {
      final env = await _prepareEnvironment(prefix);
      // Use a timeout to avoid hanging
      final completer = Completer<bool>();
      
      final process = await Process.start('winecfg', [], environment: env);
      
      // Set a timeout
      Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          process.kill();
          completer.complete(false);
        }
      });
      
      // Check exit code
      process.exitCode.then((code) {
        if (!completer.isCompleted) {
          completer.complete(code == 0);
        }
      });
      
      return await completer.future;
    } catch (e) {
      return false;
    }
  }

  /// Checks if wineserver is running for a specific Wine prefix
  Future<bool> _isWineServerRunning(String prefixPath) async {
    try {
      // Check for wineserver processes with the WINEPREFIX environment variable set to this prefix
      final result = await Process.run('ps', ['aux']);
      final lines = result.stdout.toString().split('\n');
      
      // Look for processes with WINEPREFIX=<path> in their environment
      for (final line in lines) {
        if (line.contains('wineserver') && line.contains(prefixPath)) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      _logService.log('Error checking if wineserver is running: $e', LogLevel.error);
      return false;
    }
  }

  /// Checks VC++ redistributables installation via registry (comprehensive check for 2005-2022)
  Future<Map<String, bool>> _checkVcppRedistributablesRegistry(WinePrefix prefix, Map<String, String> env) async {
    final result = {
      'vcredist_x64': false,
      'vcredist_x86': false,
      'vcredist_legacy': false,
    };
    
    try {
      final winePath = env['WINE'] ?? 'wine';
      final shell = Shell(environment: env, verbose: false);
      
      // Registry paths to check for different VC++ versions
      final registryChecks = [
        // VC++ 2015-2022 (current)
        'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X64',
        'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86',
        'HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\X86',
        'HKLM\\SOFTWARE\\Microsoft\\DevDiv\\VC\\Servicing\\14.0\\RuntimeMinimum',
        
        // VC++ 2013
        'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\12.0\\VC\\Runtimes\\x64',
        'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\12.0\\VC\\Runtimes\\x86',
        
        // VC++ 2012
        'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\11.0\\VC\\Runtimes\\x64',
        'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\11.0\\VC\\Runtimes\\x86',
        
        // VC++ 2010
        'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\10.0\\VC\\VCRedist\\x64',
        'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\10.0\\VC\\VCRedist\\x86',
        
        // VC++ 2008
        'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\9.0\\VC\\VCRedist\\x64',
        'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\9.0\\VC\\VCRedist\\x86',
        
        // VC++ 2005
        'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\8.0\\VC\\VCRedist\\x64',
        'HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\8.0\\VC\\VCRedist\\x86',
      ];
      
      int detectedX64 = 0;
      int detectedX86 = 0;
      int detectedLegacy = 0;
      
      for (final regPath in registryChecks) {
        try {
          final regCheck = await shell.runExecutableArguments(winePath, [
            'reg', 'query', regPath
          ]);
          
          if (regCheck.exitCode == 0) {
            final isX64 = regPath.contains('X64') || regPath.contains('x64');
            final isX86 = regPath.contains('X86') || regPath.contains('x86');
            final isLegacy = regPath.contains('8.0') || regPath.contains('9.0') || 
                           regPath.contains('10.0') || regPath.contains('11.0') || 
                           regPath.contains('12.0');
            
            if (isX64) detectedX64++;
            if (isX86) detectedX86++;
            if (isLegacy) detectedLegacy++;
            
            _logService.log('VC++ registry entry detected: $regPath');
          }
        } catch (e) {
          // Continue checking other paths
          continue;
        }
      }
      
      // Set results based on detections
      result['vcredist_x64'] = detectedX64 > 0;
      result['vcredist_x86'] = detectedX86 > 0;
      result['vcredist_legacy'] = detectedLegacy > 0;
      
      _logService.log('VC++ detection summary: x64: $detectedX64, x86: $detectedX86, legacy: $detectedLegacy');
      
    } catch (e) {
      _logService.log('Error checking VC++ registry: $e', LogLevel.warning);
    }
    
    return result;
  }
  
  /// Checks winetricks installed components by reading the winetricks cache/log
  Future<List<String>> _checkWinetricksInstalledComponents(WinePrefix prefix, Map<String, String> env) async {
    final installedComponents = <String>[];
    
    try {
      // Check winetricks cache directory for installed verbs
      final cacheDir = path.join(prefix.path, 'drive_c', 'windows', 'Installer');
      final cacheDirectory = Directory(cacheDir);
      
      if (await cacheDirectory.exists()) {
        await for (final entity in cacheDirectory.list()) {
          if (entity is Directory) {
            final dirName = path.basename(entity.path);
            // Common winetricks patterns
            if (dirName.startsWith('vcrun') || 
                dirName.startsWith('dotnet') ||
                dirName.startsWith('directx') ||
                dirName.startsWith('xna') ||
                dirName.contains('redist')) {
              installedComponents.add(dirName);
            }
          }
        }
      }
      
      // Also check for winetricks log file
      final winetricksLog = File(path.join(prefix.path, 'winetricks.log'));
      if (await winetricksLog.exists()) {
        final logContent = await winetricksLog.readAsString();
        final logLines = logContent.split('\n');
        
        for (final line in logLines) {
          if (line.contains('Installing') && line.contains('verb')) {
            final match = RegExp(r'Installing (\w+)').firstMatch(line);
            if (match != null) {
              final component = match.group(1)!;
              if (!installedComponents.contains(component)) {
                installedComponents.add(component);
              }
            }
          }
        }
      }
      
      _logService.log('Detected winetricks components: ${installedComponents.join(', ')}');
      
    } catch (e) {
      _logService.log('Error checking winetricks components: $e', LogLevel.warning);
    }
    
    return installedComponents;
  }
}
