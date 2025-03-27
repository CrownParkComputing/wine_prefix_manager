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
          final prefixName = path.basename(entry.path);
          // Basic check for a Wine/Proton prefix (presence of system.reg)
          final systemReg = File(path.join(entry.path, 'system.reg'));

          if (await systemReg.exists()) {
            print('Found potential prefix: ${entry.path}');
            // Try to load configuration to get build path and type
            String? buildPath;
            PrefixType type = PrefixType.wine; // Default to wine
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
               print('  - Config file (.prefix_config) not found for $prefixName.');
               // Cannot determine build path or specific type without config
               // Consider adding logic here if you want to *guess* the type or leave buildPath empty
            }

            // Create the WinePrefix object
            // Note: ExeEntries are loaded separately (e.g., by PrefixStorageService)
            final prefix = WinePrefix(
              name: prefixName,
              path: entry.path,
              wineBuildPath: buildPath ?? '', // Use empty string if not found
              type: type,
              exeEntries: [], // Scanner doesn't load exe entries
            );
            foundPrefixes.add(prefix);
          }
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