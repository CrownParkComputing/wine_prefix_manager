import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as path;
import '../models/settings.dart';
import '../models/wine_build.dart';
import '../models/prefix_models.dart'; // Import PrefixType
import 'wine_component_installer.dart'; // Import the installer
import 'log_service.dart'; // Import LogService

typedef StatusCallback = void Function(String status);
typedef ProgressCallback = void Function(double progress); // Progress 0.0 to 1.0

class PrefixCreationService {
  final Dio _dio = Dio();
  final Shell _shell = Shell(verbose: false); // Keep shell operations quiet by default
  final WineComponentInstaller _componentInstaller = WineComponentInstaller(); // Instantiate installer
  final LogService _logService = LogService(); // Get instance for logging within service

  Future<WinePrefix?> downloadAndCreatePrefix({
    required BaseBuild? selectedBuild, // Make nullable
    required String prefixName,
    required Settings settings,
    required PrefixType prefixType, // Added parameter for explicit type
    required StatusCallback onStatusUpdate,
    required ProgressCallback onProgressUpdate,
  }) async {
    onStatusUpdate('Starting prefix creation for "$prefixName" (${prefixType.name})...');
    _logService.log('Starting prefix creation for "$prefixName" (${prefixType.name})...');

    // --- Handle Gaming Prefix Type (Uses System Wine) ---
    if (prefixType == PrefixType.gaming) {
      try {
        onStatusUpdate('Creating Gaming prefix directory...');
        String prefixPath = _getPrefixPath(settings, prefixName);
        await Directory(prefixPath).create(recursive: true);
        _logService.log('Gaming prefix directory created at: $prefixPath');

        // Save config indicating system wine is used
        final configFile = File(path.join(prefixPath, '.prefix_config'));
        await configFile.writeAsString(jsonEncode({
          'buildPath': 'system', // Indicate system wine
          'type': prefixType.toString()
        }));
        _logService.log('Gaming prefix config saved.');

        // Initialize and configure the gaming prefix using system wine
        await _initializeGamingPrefix(prefixPath, settings, onStatusUpdate);

        onStatusUpdate('Gaming prefix "$prefixName" created successfully!');
        _logService.log('Gaming prefix "$prefixName" created successfully!');

        return WinePrefix(
          name: prefixName,
          path: prefixPath,
          wineBuildPath: 'system', // Indicate system wine was used
          type: prefixType,
          exeEntries: [],
        );
      } catch (e, stackTrace) {
        _logService.log('Error creating Gaming prefix "$prefixName": $e\n$stackTrace', LogLevel.error);
        onStatusUpdate('Error creating Gaming prefix "$prefixName": $e');
        return null;
      }
    }

    // --- Handle Standard Wine/Proton Prefix Types (Requires a selected build) ---
    if (selectedBuild == null) {
      onStatusUpdate('Error: A build must be selected for Wine/Proton prefixes.');
      _logService.log('Prefix creation failed: No build selected for non-gaming type.', LogLevel.error);
      return null;
    }

    // Verify build type matches selected prefix type (optional but good practice)
    // Note: We allow using Proton-GE builds (type: proton) for Proton prefixes
    if (prefixType == PrefixType.wine && selectedBuild.type != PrefixType.wine) {
       final errorMsg = 'Error: Selected build type (${selectedBuild.type.name}) must be Wine for standard Wine prefix type.';
       onStatusUpdate(errorMsg);
       _logService.log(errorMsg, LogLevel.error);
       return null;
    }
     // Removed check for protonExperimental
     if (prefixType == PrefixType.proton && selectedBuild.type != PrefixType.proton) {
        // Currently, only Proton-GE builds (type: proton) can be used for Proton prefixes
        final errorMsg = 'Error: Selected build type (${selectedBuild.type.name}) must be Proton for Proton prefix type.';
        onStatusUpdate(errorMsg);
        _logService.log(errorMsg, LogLevel.error);
        return null;
     }
     // This check is now redundant as Gaming type is handled above
     // if (prefixType == PrefixType.gaming && selectedBuild.type != PrefixType.wine) {
     //    // Gaming prefixes must be based on a Wine build (like Kron4ek)
     //    final errorMsg = 'Error: Selected build type (${selectedBuild.type.name}) must be Wine for Gaming prefix type.';
     //    onStatusUpdate(errorMsg);
     //    _logService.log(errorMsg, LogLevel.error);
     //    return null;
     // }

    // Ensure we have a downloadable build if installPath is not set
    if (selectedBuild.installPath == null && selectedBuild.downloadUrl == null) {
       const errorMsg = 'Error: Selected build has no download URL and no install path.'; // Made const
       onStatusUpdate(errorMsg);
       _logService.log(errorMsg, LogLevel.error);
       return null;
    }
    // Prevent creation from installed builds for now
    if (selectedBuild.installPath != null) {
       const errorMsg = 'Error: Creating prefixes from installed Steam builds is not yet supported.'; // Made const
       onStatusUpdate(errorMsg);
       _logService.log(errorMsg, LogLevel.error);
       return null;
    }

    try {
      // --- Download and Extract (only if not installed) ---
      String extractedDir;
      if (selectedBuild.installPath == null) {
         // We've already checked downloadUrl is not null
         final String downloadUrl = selectedBuild.downloadUrl!;

         // 1. Download Build
         onStatusUpdate('Downloading ${selectedBuild.name}...');
         _logService.log('Downloading ${selectedBuild.name} from $downloadUrl...');
         final downloadDir = await _getDownloadDirectory(selectedBuild.type); // Use build's type for download location
         await Directory(downloadDir).create(recursive: true);
         final fileName = selectedBuild.name;
         final filePath = path.join(downloadDir, fileName);

         if (!File(filePath).existsSync()) {
            _logService.log('Starting download to $filePath');
            await _dio.download(
               downloadUrl, // Use the non-null downloadUrl
               filePath,
               onReceiveProgress: (received, total) {
                  if (total > 0) {
                     double progress = received / total;
                     onProgressUpdate(progress);
                     final progressPercent = (progress * 100).toStringAsFixed(1);
                     // Only update status less frequently to avoid UI churn
                     if (received % (1024 * 1024 * 5) == 0 || received == total) { // Update every ~5MB or at the end
                        onStatusUpdate('Downloading: $progressPercent%');
                     }
                  } else {
                     onStatusUpdate('Downloading: ${received ~/ 1024} KB...');
                  }
               },
            );
            onProgressUpdate(1.0);
            onStatusUpdate('Download complete.');
            _logService.log('Download complete.');
         } else {
            onStatusUpdate('Build already downloaded.');
            _logService.log('Build already downloaded at $filePath.');
            onProgressUpdate(1.0);
         }

         // 2. Extract Build
         onStatusUpdate('Extracting ${selectedBuild.name}...');
         _logService.log('Extracting ${selectedBuild.name}...');
         final extractedName = fileName.replaceAll(
            selectedBuild.type == PrefixType.wine ? '.tar.xz' : '.tar.gz', // Use build's type
            ''
         );
         extractedDir = path.join(downloadDir, extractedName); // Assign to outer scope variable

         if (!await Directory(extractedDir).exists() || await Directory(extractedDir).list().isEmpty) {
            _logService.log('Extracting "$filePath" to "$downloadDir"...');
            await _shell.run('tar -xf "$filePath" -C "$downloadDir"');
            onStatusUpdate('Extraction complete.');
            _logService.log('Extraction complete.');
         } else {
            onStatusUpdate('Build already extracted.');
            _logService.log('Build already extracted at $extractedDir.');
         }

         if (!await Directory(extractedDir).exists()) {
            final errorMsg = 'Extraction failed: Directory "$extractedDir" not found after extraction attempt.';
            _logService.log(errorMsg, LogLevel.error);
            throw Exception(errorMsg);
         }
         _logService.log('Build extracted to: $extractedDir');
      } else {
         // This case should not be reached due to the check at the beginning,
         // but handle defensively. We cannot proceed without an extracted path.
         const errorMsg = "Cannot create prefix: Build is marked as installed but installPath is null."; // Made const
         _logService.log(errorMsg, LogLevel.error);
         throw Exception(errorMsg);
      }
      // --- End Download and Extract ---

      // 3. Create Prefix Directory
      onStatusUpdate('Creating prefix directory...');
      String prefixPath = _getPrefixPath(settings, prefixName);
      await Directory(prefixPath).create(recursive: true);
      _logService.log('Prefix directory created at: $prefixPath');

      // 4. Save Prefix Config
      final configFile = File(path.join(prefixPath, '.prefix_config'));
      await configFile.writeAsString(jsonEncode({
        'buildPath': extractedDir, // Use the path of the extracted build
        'type': prefixType.toString() // Store the *intended* prefix type
      }));
      _logService.log('Prefix config saved.');

      // 5. Initialize Prefix (Wine/Proton Setup)
      onStatusUpdate('Initializing prefix (this might take a moment)...');
      // Use the actual type of the build files for initialization
      await _initializeStandardPrefix(selectedBuild.type, prefixPath, extractedDir, settings, onStatusUpdate);
      _logService.log('Standard prefix initialized.');

      onStatusUpdate('Prefix "$prefixName" created successfully!');
      _logService.log('Prefix "$prefixName" created successfully!');

      // 6. Return new WinePrefix object
      return WinePrefix(
        name: prefixName,
        path: prefixPath,
        wineBuildPath: extractedDir, // Store path to the build files used
        type: prefixType, // Store the *intended* prefix type selected by the user
        exeEntries: [],
      );

    } catch (e, stackTrace) {
      // Removed print statement
      _logService.log('Error creating prefix "$prefixName": $e\n$stackTrace', LogLevel.error);
      onStatusUpdate('Error creating prefix "$prefixName": $e');
      return null;
    }
  } // End downloadAndCreatePrefix

  Future<String> _getDownloadDirectory(PrefixType type) async {
    final appDir = Directory('.').absolute.path;
    // Treat Proton the same for download location (as we only download GE)
    // Removed check for protonExperimental
    final buildDirName = (type == PrefixType.proton)
        ? "proton_builds"
        : "wine_builds";
    return path.join(appDir, buildDirName);
  }

  String _getPrefixPath(Settings settings, String prefixName) {
     String baseDir;
     if (settings.prefixDirectory.isNotEmpty && Directory(settings.prefixDirectory).existsSync()) {
        baseDir = settings.prefixDirectory;
     } else {
        final homeDir = Platform.environment['HOME'];
        if (homeDir != null) {
            baseDir = path.join(homeDir, '.local', 'share', 'wineprefixes');
        } else {
            // Use a relative path within the project if HOME is not set
            baseDir = path.join(Directory('.').absolute.path, 'wineprefixes');
            _logService.log("Warning: HOME environment variable not set. Using relative path for prefixes: $baseDir", LogLevel.warning);
        }
        if (settings.prefixDirectory.isNotEmpty) {
            // Log if the specified directory didn't exist and we fell back
            _logService.log("Warning: Specified prefix directory '${settings.prefixDirectory}' does not exist or is invalid. Falling back to '$baseDir'.", LogLevel.warning);
        }
     }
     Directory(baseDir).createSync(recursive: true);
     return path.join(baseDir, prefixName);
  }


  Future<void> _initializeStandardPrefix(PrefixType buildType, String prefixPath, String buildPath, Settings settings, StatusCallback onStatusUpdate) async {
    // Note: buildType here refers to the type of the *files* being used (Wine or Proton-GE)
    // not necessarily the intended final prefix type selected by the user.
    final baseEnv = {
      'WINEPREFIX': prefixPath,
      'PATH': '$buildPath/bin:${Platform.environment['PATH']}', // Adjusted path for GE/Wine structure
      'LD_LIBRARY_PATH': '$buildPath/lib64:$buildPath/lib:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}', // Adjusted path
      'GST_PLUGIN_SYSTEM_PATH_1_0': '',
      'WINEDLLOVERRIDES': 'winemenubuilder.exe=d',
    };

    // Proton-GE builds require Proton environment variables
    if (buildType == PrefixType.proton) {
      baseEnv['STEAM_COMPAT_CLIENT_INSTALL_PATH'] = Platform.environment['HOME'] ?? '.';
      baseEnv['STEAM_COMPAT_DATA_PATH'] = prefixPath;
      // UMU_ID might not be strictly necessary for GE outside Steam, but doesn't hurt
      baseEnv['UMU_ID'] = '1';
    }

    final fullEnv = {...Platform.environment, ...baseEnv};
    final setupShell = Shell(environment: fullEnv, verbose: false);

    _logService.log('Initializing standard prefix using build type: ${buildType.name} from $buildPath');

    // Determine the correct wine executable based on build type
    String wineExecutablePath;
    if (buildType == PrefixType.wine) {
       wineExecutablePath = path.join(buildPath, 'bin', 'wine');
    } else { // Proton-GE
       wineExecutablePath = path.join(buildPath, 'bin', 'wine'); // GE structure also has wine in bin
    }

    if (!await File(wineExecutablePath).exists()) {
        final errorMsg = 'Could not find wine executable at $wineExecutablePath';
        _logService.log(errorMsg, LogLevel.error);
        throw Exception(errorMsg);
    }
    _logService.log('Using wine executable: $wineExecutablePath');

    // Ensure it's executable
    try {
      await Shell(verbose: false).run('chmod +x "$wineExecutablePath"');
    } catch (e) {
       _logService.log('Warning: Could not set executable permission for wine: $e', LogLevel.warning);
    }

    // Run wineboot -u for both Wine and Proton-GE initialization
    // winecfg is generally not needed for initial setup and can be run later by the user.
    onStatusUpdate('Running wineboot...');
    _logService.log('Running wineboot -u...');
    await setupShell.run('"$wineExecutablePath" wineboot -u');

    _logService.log('Standard prefix initialization command finished.');
  }

  /// Initializes a Gaming prefix using system wine and installs components.
  Future<void> _initializeGamingPrefix(String prefixPath, Settings settings, StatusCallback onStatusUpdate) async {
    _logService.log('Initializing Gaming prefix at $prefixPath using system wine...');
    const wineExecutable = 'wine'; // Assume system wine is in PATH // Made const
    final setupShell = Shell(environment: {'WINEPREFIX': prefixPath}, verbose: false);

    try {
      // 1. Initialize with wineboot
      onStatusUpdate('Initializing prefix with wineboot...');
      _logService.log('Running $wineExecutable wineboot -u...');
      await setupShell.run('$wineExecutable wineboot -u');
      _logService.log('wineboot finished.');

      // 2. Set Windows version to win10
      onStatusUpdate('Setting Windows version to win10...');
      _logService.log('Running $wineExecutable winecfg /v win10...');
      await setupShell.run('$wineExecutable winecfg /v win10');
      _logService.log('Windows version set.');

      // 3. Install dependencies
      final dependencies = [
        'corefonts', // Use corefonts instead of individual fonts
        'd3dx9', 'd3dcompiler_43', 'd3dcompiler_47', 'msls31', 'mono', 'gecko' // Keep others
      ];

      for (final component in dependencies) {
        onStatusUpdate('Installing $component...');
        _logService.log('Installing component: $component');
        try {
          await _componentInstaller.installComponent(
            prefixPath: prefixPath,
            component: component,
            wineExecutablePath: wineExecutable, // Use system wine
            onStatusUpdate: (status) { // Pass status updates through
              onStatusUpdate('Installing $component: $status');
              _logService.log('Component Installer ($component): $status');
            },
          );
          _logService.log('Successfully installed $component.');
        } catch (e) {
          _logService.log('Failed to install component $component: $e', LogLevel.error);
          onStatusUpdate('Error installing $component: $e');
          // Decide whether to continue or re-throw
          // For now, log the error and continue with other components
        }
      }
      _logService.log('Finished installing gaming dependencies.');

      // 4. Install DXVK (for DirectX 9, 10, 11)
      onStatusUpdate('Installing DXVK...');
      _logService.log('Installing DXVK...');
      try {
        // Need a temporary WinePrefix object to pass to the installer
        final tempPrefix = WinePrefix(name: path.basename(prefixPath), path: prefixPath, wineBuildPath: 'system', type: PrefixType.gaming, exeEntries: []);
        await _componentInstaller.installDxvk(tempPrefix, settings, progressCallback: onStatusUpdate);
        _logService.log('DXVK installation attempted.');
      } catch (e) {
        _logService.log('Failed to install DXVK: $e', LogLevel.error);
        onStatusUpdate('Error installing DXVK: $e');
      }

      // 5. Install VKD3D-Proton (for DirectX 12)
      onStatusUpdate('Installing VKD3D-Proton...');
      _logService.log('Installing VKD3D-Proton...');
      try {
        final tempPrefix = WinePrefix(name: path.basename(prefixPath), path: prefixPath, wineBuildPath: 'system', type: PrefixType.gaming, exeEntries: []);
        await _componentInstaller.installVkd3d(tempPrefix, settings, progressCallback: onStatusUpdate);
        _logService.log('VKD3D-Proton installation attempted.');
      } catch (e) {
        _logService.log('Failed to install VKD3D-Proton: $e', LogLevel.error);
        onStatusUpdate('Error installing VKD3D-Proton: $e');
      }

      // 6. Run winetricks verbs to ensure proper configuration/overrides
      final winetricksVerbs = ['dxvk', 'vkd3d', 'dxvk_nvapi']; // Add dxvk_nvapi
      for (final verb in winetricksVerbs) {
         onStatusUpdate('Configuring $verb via winetricks...');
         _logService.log('Running winetricks $verb...');
         try {
            await _componentInstaller.installComponent(
               prefixPath: prefixPath,
               component: verb,
               wineExecutablePath: wineExecutable, // Use system wine
               onStatusUpdate: (status) {
                  onStatusUpdate('Configuring $verb: $status');
                  _logService.log('Winetricks ($verb): $status');
               },
            );
            _logService.log('Winetricks configuration for $verb completed.');
         } catch (e) {
            _logService.log('Failed to configure $verb via winetricks: $e', LogLevel.warning); // Log as warning, might not be critical
            onStatusUpdate('Warning: Failed to configure $verb: $e');
         }
      }

    } catch (e, stackTrace) {
      _logService.log('Error during Gaming prefix initialization: $e\n$stackTrace', LogLevel.error);
      onStatusUpdate('Error initializing Gaming prefix: $e');
      rethrow; // Re-throw to be caught by the main function
    }
  }
}