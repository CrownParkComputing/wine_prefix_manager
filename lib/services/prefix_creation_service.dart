import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as path;
import '../models/settings.dart';
import '../models/wine_build.dart';
import '../models/prefix_models.dart'; // For PrefixType and WinePrefix

typedef StatusCallback = void Function(String status);
typedef ProgressCallback = void Function(double progress); // Progress 0.0 to 1.0

class PrefixCreationService {
  final Dio _dio = Dio();
  final Shell _shell = Shell(verbose: false); // Keep shell operations quiet by default

  Future<WinePrefix?> downloadAndCreatePrefix({
    required BaseBuild selectedBuild,
    required String prefixName,
    required Settings settings,
    required StatusCallback onStatusUpdate,
    required ProgressCallback onProgressUpdate,
  }) async {
    onStatusUpdate('Starting prefix creation for "$prefixName"...');

    try {
      // 1. Download Build
      onStatusUpdate('Downloading ${selectedBuild.name}...');
      final downloadDir = await _getDownloadDirectory(selectedBuild.type);
      await Directory(downloadDir).create(recursive: true);
      final fileName = selectedBuild.name; // Assuming name is the filename from the build object
      final filePath = path.join(downloadDir, fileName); // Use path.join for robustness

      if (!File(filePath).existsSync()) {
        await _dio.download(
          selectedBuild.downloadUrl,
          filePath,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              double progress = received / total;
              onProgressUpdate(progress);
              final progressPercent = (progress * 100).toStringAsFixed(1);
              onStatusUpdate('Downloading: $progressPercent%');
            } else {
              // Indicate indeterminate progress if total is unknown
              onStatusUpdate('Downloading: ${received ~/ 1024} KB...');
            }
          },
        );
        onProgressUpdate(1.0); // Ensure progress reaches 100%
        onStatusUpdate('Download complete.');
      } else {
        onStatusUpdate('Build already downloaded.');
        onProgressUpdate(1.0); // Indicate download step is complete
      }

      // 2. Extract Build
      onStatusUpdate('Extracting ${selectedBuild.name}...');
      // Determine extracted directory name (handle potential variations)
      final extractedName = fileName.replaceAll(
        selectedBuild.type == PrefixType.wine ? '.tar.xz' : '.tar.gz',
        ''
      );
      final extractedDir = path.join(downloadDir, extractedName);

      // Avoid re-extracting if directory already exists and seems valid
      if (!await Directory(extractedDir).exists() || await Directory(extractedDir).list().isEmpty) {
         print('Extracting "$filePath" to "$downloadDir"...');
         // Use Shell for extraction
         // Ensure paths with spaces are quoted
         await _shell.run('tar -xf "$filePath" -C "$downloadDir"');
         onStatusUpdate('Extraction complete.');
      } else {
         onStatusUpdate('Build already extracted.');
      }

      // Verify extraction
      if (!await Directory(extractedDir).exists()) {
        throw Exception('Extraction failed: Directory "$extractedDir" not found after extraction attempt.');
      }
      print('Build extracted to: $extractedDir');


      // 3. Create Prefix Directory
      onStatusUpdate('Creating prefix directory...');
      String prefixPath = _getPrefixPath(settings, prefixName);
      await Directory(prefixPath).create(recursive: true);
      print('Prefix directory created at: $prefixPath');

      // 4. Save Prefix Config
      final configFile = File(path.join(prefixPath, '.prefix_config'));
      await configFile.writeAsString(jsonEncode({
        'buildPath': extractedDir, // Store the absolute path to the build
        'type': selectedBuild.type == PrefixType.proton ? 'proton' : 'wine'
      }));
      print('Prefix config saved.');

      // 5. Initialize Prefix (Wine/Proton Setup)
      onStatusUpdate('Initializing prefix (this might take a moment)...');
      await _initializePrefix(selectedBuild.type, prefixPath, extractedDir, settings);
      print('Prefix initialized.');

      onStatusUpdate('Prefix "$prefixName" created successfully!');

      // 6. Return new WinePrefix object
      return WinePrefix(
        name: prefixName,
        path: prefixPath,
        wineBuildPath: extractedDir, // Store the path to the extracted build
        type: selectedBuild.type,
        exeEntries: [], // Start with empty entries
      );

    } catch (e, stackTrace) {
      print('Error creating prefix "$prefixName": $e\n$stackTrace');
      onStatusUpdate('Error creating prefix "$prefixName": $e');
      return null; // Indicate failure
    }
  }

  Future<String> _getDownloadDirectory(PrefixType type) async {
    // Use path.join for correctness, relative to the application directory
    final appDir = '.'; // Assuming the app runs from its root directory
    return path.join(appDir, type == PrefixType.wine ? "wine_builds" : "proton_builds");
  }

  String _getPrefixPath(Settings settings, String prefixName) {
     String baseDir;
     // Use prefixDirectory from settings if it's set and exists, otherwise fallback
     if (settings.prefixDirectory.isNotEmpty && Directory(settings.prefixDirectory).existsSync()) {
        baseDir = settings.prefixDirectory;
     } else {
        // Sensible fallback if prefixDirectory is not set or doesn't exist
        final homeDir = Platform.environment['HOME'];
        if (homeDir != null) {
            baseDir = path.join(homeDir, '.local', 'share', 'wineprefixes');
        } else {
            // Absolute fallback if HOME is not set (less likely)
            baseDir = path.join('.', '.local', 'share', 'wineprefixes');
            print("Warning: HOME environment variable not set. Using relative path for prefixes.");
        }
        if (settings.prefixDirectory.isNotEmpty) {
            print("Warning: Specified prefix directory '${settings.prefixDirectory}' does not exist. Falling back to '$baseDir'.");
        }
     }
     // Ensure baseDir exists before joining
     Directory(baseDir).createSync(recursive: true);
     return path.join(baseDir, prefixName);
  }


  Future<void> _initializePrefix(PrefixType type, String prefixPath, String buildPath, Settings settings) async {
    final baseEnv = {
      'WINEPREFIX': prefixPath,
      'PATH': '$buildPath/bin:${Platform.environment['PATH']}',
      'LD_LIBRARY_PATH': '$buildPath/lib:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
      'GST_PLUGIN_SYSTEM_PATH_1_0': '', // May need adjustment
      'WINEDLLOVERRIDES': 'winemenubuilder.exe=d', // Prevent menu items creation
    };

    if (type == PrefixType.proton) {
      // These might be necessary for some Proton features/games
      baseEnv['STEAM_COMPAT_CLIENT_INSTALL_PATH'] = Platform.environment['HOME'] ?? '.'; // Or actual Steam install path?
      baseEnv['STEAM_COMPAT_DATA_PATH'] = prefixPath;
    }

    final fullEnv = {...Platform.environment, ...baseEnv};
    // Use a separate shell instance for setup to manage environment
    final setupShell = Shell(environment: fullEnv, verbose: false);

    print('Initializing prefix type: ${type.name}');
    if (type == PrefixType.wine) {
      // Run winecfg to initialize. It might open a window.
      print('Running winecfg in $prefixPath...');
      await setupShell.run('"$buildPath/bin/winecfg"');
    } else {
      // Run dummy script with Proton to initialize
      final dummyScriptName = '_init_dummy.bat';
      final dummyScriptPath = path.join(prefixPath, dummyScriptName);

      try {
        // Use CRLF for batch file line endings
        await File(dummyScriptPath).writeAsString('echo Initializing Proton Prefix...\r\nexit 0');
        print('Running dummy script with Proton in $prefixPath...');
        // Ensure proton executable and script path are quoted
        await setupShell.run('"$buildPath/proton" run "$dummyScriptPath"');
      } finally {
         // Clean up dummy script
         final file = File(dummyScriptPath);
         if (await file.exists()) {
            await file.delete();
            print('Deleted dummy script.');
         }
      }
    }
    print('Prefix initialization command finished.');
  }
}