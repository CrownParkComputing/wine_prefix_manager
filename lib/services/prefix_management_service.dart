import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/settings.dart';
import '../models/prefix_models.dart';

class PrefixManagementService {

  /// Scans the prefix directory specified in settings for existing Wine/Proton prefixes.
  /// Returns a list of discovered WinePrefix objects.
  Future<List<WinePrefix>> scanForExistingPrefixes(Settings settings) async {
    List<WinePrefix> foundPrefixes = [];
    final prefixBaseDir = settings.prefixDirectory; // Use the primary directory for scanning

    if (prefixBaseDir.isEmpty || !await Directory(prefixBaseDir).exists()) {
      print('Prefix directory not set or does not exist: $prefixBaseDir. Cannot scan.');
      return foundPrefixes; // Return empty list if base directory is invalid
    }

    print('Scanning for prefixes in: $prefixBaseDir');
    final dir = Directory(prefixBaseDir);

    try {
      await for (final entry in dir.list()) {
        if (entry is Directory) {
          print('Checking directory: ${entry.path}'); // Add logging here
          final prefixName = path.basename(entry.path);

          // --- Check for registry files ---
          final systemRegPath = path.join(entry.path, 'system.reg');
          final userRegPath = path.join(entry.path, 'user.reg');
          final systemRegExists = await File(systemRegPath).exists();
          final userRegExists = await File(userRegPath).exists();

          // Declare variables needed in multiple scopes
          String? buildPath;
          PrefixType type = PrefixType.wine; // Default to wine
          String actualPrefixPath = entry.path; // Path containing .reg files (might change if nested)
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
                print('Found potential prefix nested in pfx: ${entry.path} (system.reg: $systemRegPfxExists, user.reg: $userRegPfxExists)');
                actualPrefixPath = pfxPath; // Update the path where .reg files are found
                foundRegFiles = true; // Mark as found
              }
            }
          }
          // --- End Check for registry files ---


          // --- Process if registry files were found ---
          if (foundRegFiles) {
            print('Processing prefix: ${entry.path}');

            // Config file should always be in the root directory (entry.path)
            final configFile = File(path.join(entry.path, '.prefix_config'));

            if (await configFile.exists()) {
              try {
                final configContent = await configFile.readAsString();
                final config = json.decode(configContent);
                buildPath = config['buildPath'] as String?;
                type = (config['type'] as String? ?? 'wine') == 'proton'
                    ? PrefixType.proton
                    : PrefixType.wine;
                 print('  - Config found: Type=${type.name}, BuildPath=$buildPath');
              } catch (e) {
                 print('  - Error reading config file for $prefixName: $e');
                 // Proceed without build path if config is corrupt
              }
            } else {
              print('  - Config file (.prefix_config) not found for $prefixName. Attempting to recreate.');
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
                'type': type.name,
                // Add other default fields if necessary in the future
              };

              try {
                await configFile.writeAsString(json.encode(defaultConfig));
                print('  - Created default .prefix_config for $prefixName (Type: ${type.name}). Please verify build path later.');
              } catch (e) {
                print('  - Failed to create default .prefix_config for $prefixName: $e');
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
            print('Skipping directory (no system.reg or user.reg found in root or pfx): ${entry.path}');
          }
          // --- End Process if registry files were found ---

        }
      }
      print('Scan complete. Found ${foundPrefixes.length} prefixes.');
    } catch (e) {
      print('Error scanning for prefixes in $prefixBaseDir: $e');
      // Depending on requirements, might rethrow or return partial list
    }

    return foundPrefixes;
  }

  // Future methods for addExeToPrefix, deletePrefix, etc., could be added here later.
}