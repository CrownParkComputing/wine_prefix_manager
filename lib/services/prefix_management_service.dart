import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:process_run/shell.dart'; // Import Shell
import '../models/settings.dart';
import '../models/prefix_models.dart';

class PrefixManagementService {

  /// Scans the prefix directory specified in settings for existing Wine/Proton prefixes.
  /// Returns a list of discovered WinePrefix objects.
  Future<List<WinePrefix>> scanForExistingPrefixes(Settings settings) async {
    List<WinePrefix> foundPrefixes = [];
    final prefixBaseDir = settings.prefixDirectory; // Use the primary directory for scanning

    if (prefixBaseDir.isEmpty || !await Directory(prefixBaseDir).exists()) {
      // Prefix directory not set or does not exist. Cannot scan.
      return foundPrefixes; // Return empty list if base directory is invalid
    }

    // Scanning for prefixes in: $prefixBaseDir
    final dir = Directory(prefixBaseDir);

    try {
      await for (final entry in dir.list()) {
        if (entry is Directory) {
          // Checking directory: ${entry.path}
          final prefixName = path.basename(entry.path);

          // --- Check for registry files ---
          final systemRegPath = path.join(entry.path, 'system.reg');
          final userRegPath = path.join(entry.path, 'user.reg');
          final systemRegExists = await File(systemRegPath).exists();
          final userRegExists = await File(userRegPath).exists();

          // Declare variables needed in multiple scopes
          String? buildPath;
          PrefixType type = PrefixType.wine; // Default to wine
          // String actualPrefixPath = entry.path; // Removed unused variable
          bool foundRegFiles = systemRegExists || userRegExists; // Flag if .reg found in root

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
                // actualPrefixPath = pfxPath; // Removed assignment to unused variable
                foundRegFiles = true; // Mark as found
              }
            }
          }
          // --- End Check for registry files ---


          // --- Process if registry files were found ---
          if (foundRegFiles) {
            // Processing prefix: ${entry.path}

            // Config file should always be in the root directory (entry.path)
            final configFile = File(path.join(entry.path, '.prefix_config'));

            if (await configFile.exists()) {
              try {
                final configContent = await configFile.readAsString();
                final config = json.decode(configContent);
                buildPath = config['buildPath'] as String?;
                final typeString = config['type'] as String? ?? 'PrefixType.wine'; // Default if missing
                if (typeString == 'PrefixType.proton') {
                  type = PrefixType.proton;
                // } else if (typeString == 'PrefixType.protonExperimental') { // Removed check
                //   type = PrefixType.protonExperimental;
                } else if (typeString == 'PrefixType.gaming') {
                  type = PrefixType.gaming;
                } else {
                  type = PrefixType.wine; // Default to wine for unknown or "PrefixType.wine"
                }
                // Config found
              } catch (e) {
                 // Error reading config file
                 // Proceed without build path if config is corrupt
              }
            } else {
              // Config file (.prefix_config) not found. Attempting to recreate.
              // Guess type based on name
              if (prefixName.toLowerCase().contains('proton')) {
                type = PrefixType.proton;
              } else {
                type = PrefixType.wine; // Default guess
              }
              buildPath = null; // Cannot determine build path

              // Create default config content
              final defaultConfig = {
                'buildPath': buildPath,
                'type': type.name, // Use enum name directly
                // Add other default fields if necessary in the future
              };

              try {
                await configFile.writeAsString(json.encode(defaultConfig));
                // Created default .prefix_config. Please verify build path later.
              } catch (e) {
                // Failed to create default .prefix_config
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

          } else {
            // Log directories skipped due to missing registry files
            // Skipping directory (no system.reg or user.reg found in root or pfx)
          }
          // --- End Process if registry files were found ---

        }
      }
      // Scan complete. Found prefixes.
    } catch (e) {
      // Error scanning for prefixes
      // Depending on requirements, might rethrow or return partial list
    }

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

    if (prefix.type == PrefixType.proton) {
      wineBinSubDir = path.join('files', 'bin');
    } else if (prefix.type == PrefixType.gaming) {
       wineBinaryName = 'wine';
       wineServerBinaryName = 'wineserver';
       wineBuildPath = '';
       wineBinSubDir = '';
    }

    String winePath = wineBuildPath.isNotEmpty ? path.join(wineBuildPath, wineBinSubDir, wineBinaryName) : wineBinaryName;
    String wineServerPath = wineBuildPath.isNotEmpty ? path.join(wineBuildPath, wineBinSubDir, wineServerBinaryName) : wineServerBinaryName;
    String wineBinDir = wineBuildPath.isNotEmpty ? path.dirname(winePath) : '';

    String wineLibDir = '';
    String wineLib64Dir = '';
    if (wineBuildPath.isNotEmpty) {
       String libSubDir = prefix.type == PrefixType.proton ? path.join('files', 'lib') : 'lib';
       String lib64SubDir = prefix.type == PrefixType.proton ? path.join('files', 'lib64') : 'lib64';
       wineLibDir = path.join(wineBuildPath, libSubDir);
       wineLib64Dir = path.join(wineBuildPath, lib64SubDir);
    }

    // Check if wine executable exists only if a specific path is constructed
    if (wineBuildPath.isNotEmpty && !await File(winePath).exists()) {
       throw Exception('Wine executable not found at $winePath');
    }

    final env = {
      ...Platform.environment,
      'WINEPREFIX': prefix.path,
      if (wineBuildPath.isNotEmpty) ...{
         'PATH': '$wineBinDir:${Platform.environment['PATH'] ?? ''}',
         'LD_LIBRARY_PATH': '$wineLib64Dir:$wineLibDir:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
         'WINE': winePath,
         'WINESERVER': wineServerPath,
      },
      if (prefix.type == PrefixType.proton) ...{
        'STEAM_COMPAT_DATA_PATH': prefix.path,
        'STEAM_COMPAT_CLIENT_INSTALL_PATH': Platform.environment['HOME'] ?? '.',
        'SteamAppId': prefix.exeEntries.firstWhere((e) => e.steamAppId != null, orElse: () => const ExeEntry(path: '', name: '', steamAppId: 0)).steamAppId?.toString() ?? '0',
        'SteamGameId': prefix.exeEntries.firstWhere((e) => e.steamAppId != null, orElse: () => const ExeEntry(path: '', name: '', steamAppId: 0)).steamAppId?.toString() ?? '0',
        'STEAM_COMPAT_APP_ID': prefix.exeEntries.firstWhere((e) => e.steamAppId != null, orElse: () => const ExeEntry(path: '', name: '', steamAppId: 0)).steamAppId?.toString() ?? '0',
      }
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

  // Removed Winetricks verb methods

}