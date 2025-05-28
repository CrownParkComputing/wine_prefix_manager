import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as path;
import '../models/settings.dart';
import '../models/wine_build.dart';
import '../models/prefix_models.dart';
import 'log_service.dart';
import 'wine_component_installer.dart';
import 'prefix_management_service.dart';

typedef StatusCallback = void Function(String status);
typedef ProgressCallback = void Function(double progress);

class WinePrefixCreationService {
  final Dio _dio = Dio();
  final Shell _shell = Shell(verbose: false);
  final LogService _logService = LogService();
  final WineComponentInstaller _componentInstaller = WineComponentInstaller();
  final PrefixManagementService _prefixManagementService = PrefixManagementService();

  String _getExtractedFolderName(String baseFileName) {
    // Remove common archive extensions. This could be made more robust.
    var name = baseFileName;
    const extensions = ['.tar.xz', '.tar.gz', '.tar.bz2', '.tar.zst', '.zip', '.7z'];
    for (final ext in extensions) {
      if (name.endsWith(ext)) {
        name = name.substring(0, name.length - ext.length);
        break; // Assume only one primary archive extension
      }
    }
    // If it was something like .tar.gz, .tar might remain. Handle that.
    if (name.endsWith('.tar')) {
      name = name.substring(0, name.length - '.tar'.length);
    }
    return name;
  }

  Future<WinePrefix?> createWinePrefix({
    required BaseBuild? selectedBuild,
    required String prefixName,
    required Settings settings,
    required String architecture,
    required StatusCallback onStatusUpdate,
    required ProgressCallback onProgressUpdate,
  }) async {
    onStatusUpdate('Starting Wine prefix creation for "$prefixName" ($architecture)...');
    _logService.log('Starting Wine prefix creation for "$prefixName" ($architecture)...');

    if (selectedBuild == null) {
      onStatusUpdate('Error: A build must be selected for Wine prefixes.');
      _logService.log('Wine prefix creation failed: No build selected.', LogLevel.error);
      return null;
    }

    print('CREATE_PREFIX_DEBUG: (PRINT) selectedBuild.name = ${selectedBuild.name}');
    print('CREATE_PREFIX_DEBUG: (PRINT) selectedBuild.downloadUrl = ${selectedBuild.downloadUrl}');
    print('CREATE_PREFIX_DEBUG: (PRINT) selectedBuild.installPath = ${selectedBuild.installPath}');

    // Verify the build is a Wine build
    if (selectedBuild.type != PrefixType.wine) {
      final errorMsg = 'Error: Selected build type (${selectedBuild.type.name}) must be Wine for Wine prefix type.';
      onStatusUpdate(errorMsg);
      _logService.log(errorMsg, LogLevel.error);
      return null;
    }

    // Ensure we have a downloadable build if installPath is not set
    if (selectedBuild.installPath == null && selectedBuild.downloadUrl == null) {
      const errorMsg = 'Error: Selected build has no download URL and no install path.';
      onStatusUpdate(errorMsg);
      _logService.log(errorMsg, LogLevel.error);
      return null;
    }

    // Prevent creation from installed builds for now
    if (selectedBuild.installPath != null) {
      const errorMsg = 'Error: Creating prefixes from installed Steam builds is not yet supported.';
      onStatusUpdate(errorMsg);
      _logService.log(errorMsg, LogLevel.error);
      return null;
    }

    try {
      // Download and Extract (only if not installed)
      String extractedDir;
      final String downloadUrl = selectedBuild.downloadUrl!;

      // 1. Download Build
      onStatusUpdate('Downloading ${selectedBuild.name}...');
      _logService.log('Downloading ${selectedBuild.name} from $downloadUrl...');
      final downloadDir = await _getDownloadDirectory();
      await Directory(downloadDir).create(recursive: true);

      // Use only the basename of selectedBuild.name for local file paths
      final String baseArchiveName = path.basename(selectedBuild.name);
      final filePath = path.join(downloadDir, baseArchiveName);

      final String extractedFolderName = _getExtractedFolderName(baseArchiveName);
      extractedDir = path.join(downloadDir, extractedFolderName);

      print('CREATE_PREFIX_DEBUG: (PRINT) downloadDir = $downloadDir');
      print('CREATE_PREFIX_DEBUG: (PRINT) baseArchiveName = $baseArchiveName');
      print('CREATE_PREFIX_DEBUG: (PRINT) filePath = $filePath');
      print('CREATE_PREFIX_DEBUG: (PRINT) extractedFolderName = $extractedFolderName');
      print('CREATE_PREFIX_DEBUG: (PRINT) (target) extractedDir = $extractedDir');

      if (!File(filePath).existsSync()) {
        _logService.log('Starting download to $filePath');
        await _dio.download(
          downloadUrl,
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
        final errorMsg = 'Extraction failed: Directory "$extractedDir" not found after extraction attempt. This might be due to the archive extracting to a differently named top-level folder than expected ("$extractedFolderName").';
        _logService.log(errorMsg, LogLevel.error);
        throw Exception(errorMsg);
      }
      _logService.log('Build extracted to: $extractedDir');

      // 3. Create Prefix Directory
      onStatusUpdate('Creating prefix directory...');
      String prefixPath = _getPrefixPath(settings, prefixName);
      await Directory(prefixPath).create(recursive: true);
      _logService.log('Prefix directory created at: $prefixPath');

      // 4. Save Prefix Config
      final configFile = File(path.join(prefixPath, '.prefix_config'));
      await configFile.writeAsString(jsonEncode({
        'buildPath': extractedDir,
        'type': PrefixType.wine.toString(),
        'architecture': architecture,
      }));
      _logService.log('Prefix config saved.');

      // 5. Initialize Prefix
      onStatusUpdate('Initializing prefix ($architecture, this might take a moment)...');
      print('CREATE_PREFIX_DEBUG: (PRINT) Calling _initializeWinePrefix with buildPath = $extractedDir');
      await _initializeWinePrefix(prefixPath, extractedDir, architecture, settings, onStatusUpdate, selectedBuild);
      _logService.log('Wine prefix initialized.');

      onStatusUpdate('Wine prefix "$prefixName" ($architecture) created successfully!');
      _logService.log('Wine prefix "$prefixName" ($architecture) created successfully!');

      // 6. Return new WinePrefix object
      return WinePrefix(
        name: prefixName,
        path: prefixPath,
        wineBuildPath: extractedDir,
        type: PrefixType.wine,
        architecture: architecture,
        exeEntries: [],
      );

    } catch (e, stackTrace) {
      _logService.log('Error creating Wine prefix "$prefixName": $e\n$stackTrace', LogLevel.error);
      onStatusUpdate('Error creating Wine prefix "$prefixName": $e');
      return null;
    }
  }

  Future<String> _getDownloadDirectory() async {
    final String appName = 'wine_prefix_manager';
    final String buildsSubDir = 'downloaded_builds';
    final homeDir = Platform.environment['HOME'];

    String baseDir;

    if (homeDir != null && homeDir.isNotEmpty) {
      // Preferred: User's local share directory
      baseDir = path.join(homeDir, '.local', 'share', appName, buildsSubDir);
    } else {
      // Fallback: System's temporary directory (less ideal for persistence)
      // Consider logging a warning if this happens.
      _logService.log('HOME environment variable not set. Using temporary directory for downloads.', LogLevel.warning);
      final tempDir = await Directory.systemTemp.createTemp('${appName}_downloads_');
      baseDir = tempDir.path; 
      // Note: Builds in temp might not persist across reboots or sessions.
      // This is a fallback; the primary expectation is HOME is available.
    }
    
    // Ensure the directory exists
    try {
      final dir = Directory(baseDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        _logService.log('Created download directory: $baseDir');
      }
    } catch (e) {
      _logService.log('Error creating download directory $baseDir: $e', LogLevel.error);
      // If creation fails, fall back to a truly temporary system dir as a last resort for this session
      final tempDir = await Directory.systemTemp.createTemp('wpm_dl_fallback_');
      return tempDir.path;
    }

    _logService.log('Using download directory: $baseDir');
    return baseDir;
  }

  String _getPrefixPath(Settings settings, String prefixName) {
    final homeDir = Platform.environment['HOME'];
    // Initialize with a fallback to ensure it's always assigned.
    String baseDirToUse = path.join(Directory.systemTemp.path, 'wine_prefix_manager', 'prefixes');
    _logService.log('Initial fallback for baseDirToUse: $baseDirToUse (will be overridden by preferred paths if available)', LogLevel.debug);

    bool useCustomPath = false;

    // Priority 1: User-defined absolute path in settings
    if (settings.prefixDirectory.isNotEmpty) {
      if (path.isAbsolute(settings.prefixDirectory)) {
        String userDefinedPath = settings.prefixDirectory;
        try {
          final dir = Directory(userDefinedPath);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
            _logService.log('Created user-specified absolute prefix directory: $userDefinedPath');
          }
          baseDirToUse = userDefinedPath; // Assign if valid and created/exists
          useCustomPath = true;
          _logService.log('Using user-defined absolute prefix directory: $baseDirToUse');
        } catch (e) {
          _logService.log('Error creating/accessing user-specified absolute prefix directory $userDefinedPath: $e. Falling back.', LogLevel.error);
          // useCustomPath remains false, will fall back to default logic below
        }
      } else {
         _logService.log('Warning: settings.prefixDirectory ("${settings.prefixDirectory}") is relative. Ignoring and using default app data location.', LogLevel.warning);
      }
    }

    // Priority 2: Default app data path if custom path not used or failed
    if (!useCustomPath) {
        if (homeDir != null && homeDir.isNotEmpty) {
            baseDirToUse = path.join(homeDir, '.local', 'share', 'wine_prefix_manager', 'prefixes');
            _logService.log('Using default app data directory for Wine prefixes: $baseDirToUse');
        } else {
            _logService.log('Warning: HOME environment variable not set. Using temporary directory for Wine prefixes (already set as initial fallback): $baseDirToUse', LogLevel.warning);
            // baseDirToUse is already set to the temp path as an initial fallback
        }
    }
    
    // Ensure the final chosen base directory exists
    try {
      final dir = Directory(baseDirToUse);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
        _logService.log('Ensured final base Wine prefix directory exists: $baseDirToUse');
      }
    } catch (e) {
      _logService.log('Critical Error: Could not create final base Wine prefix directory $baseDirToUse: $e.', LogLevel.error);
      throw Exception('Failed to create final base Wine prefix directory: $baseDirToUse. Error: $e');
    }
    
    // Create the type-specific subfolder (e.g., .../prefixes/wine/)
    final typeDir = path.join(baseDirToUse, 'wine');
    try {
        Directory(typeDir).createSync(recursive: true);
    } catch (e) {
        _logService.log('Critical Error: Could not create type-specific Wine prefix directory $typeDir: $e.', LogLevel.error);
        throw Exception('Failed to create type-specific Wine prefix directory: $typeDir. Error: $e');
    }
    
    _logService.log('Final Wine prefix path for "$prefixName" will be under: $typeDir');
    return path.join(typeDir, prefixName);
  }

  Future<void> _initializeWinePrefix(String prefixPath, String buildPath, String architecture, Settings settings, StatusCallback onStatusUpdate, BaseBuild selectedBuild) async {
    print('INIT_PREFIX_DEBUG: (PRINT) Received buildPath = $buildPath');
    print('INIT_PREFIX_DEBUG: (PRINT) selectedBuild.name for proton check = ${selectedBuild.name}');

    final bool isProton = selectedBuild.name.toLowerCase().contains('proton') || await File(path.join(buildPath, 'proton')).exists() || await File(path.join(buildPath, 'proton.sh')).exists();
    String effectiveWineExecutable;
    String protonScriptFileName = 'proton'; // Default to 'proton'
    
    if (isProton) {
      print('INIT_PREFIX_DEBUG: (PRINT) Proton build detected at $buildPath.');
      if (await File(path.join(buildPath, 'proton')).exists()) {
        effectiveWineExecutable = path.join(buildPath, 'proton');
        protonScriptFileName = 'proton';
      } else if (await File(path.join(buildPath, 'proton.sh')).exists()) {
        effectiveWineExecutable = path.join(buildPath, 'proton.sh');
        protonScriptFileName = 'proton.sh';
        print('INIT_PREFIX_DEBUG: (PRINT) Using proton.sh as proton script.');
      } else {
        // This case should ideally be caught by the isProton check above, but as a safeguard:
        final errorMsg = 'Proton build detected, but neither "proton" nor "proton.sh" script found in $buildPath. This should not happen if isProton was true due to file existence.';
        _logService.log(errorMsg, LogLevel.error);
        throw Exception(errorMsg);
      }
       print('INIT_PREFIX_DEBUG: (PRINT) Proton identified. Script: $protonScriptFileName in $buildPath');
    } else {
      effectiveWineExecutable = path.join(buildPath, 'bin', 'wine');
      print('INIT_PREFIX_DEBUG: (PRINT) Standard Wine build. Executable: $effectiveWineExecutable');
    }
    
    print('INIT_PREFIX_DEBUG: (PRINT) Effective Wine/Proton executable = $effectiveWineExecutable');

    Map<String, String> ldLibraryPathEntry = {};
    if (isProton) {
      print('Proton build: Clearing LD_LIBRARY_PATH to let Proton script manage it.');
      ldLibraryPathEntry = {'LD_LIBRARY_PATH': ''}; // Clear it for Proton
    } else {
      ldLibraryPathEntry = {'LD_LIBRARY_PATH': '$buildPath/lib64:$buildPath/lib:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}'};
    }

    final baseEnv = {
      'WINEPREFIX': prefixPath,
      'WINEARCH': architecture,
      'PATH': '${path.dirname(effectiveWineExecutable)}:${Platform.environment['PATH'] ?? ''}',
      ...ldLibraryPathEntry,
      'GST_PLUGIN_SYSTEM_PATH_1_0': '', // Clear GStreamer path to avoid conflicts
      'WINEDLLOVERRIDES': 'winemenubuilder.exe=d',
      'WINE': effectiveWineExecutable, // For Winetricks, Proton script handles this
    };

    // Merge Platform.environment first, so baseEnv can override specific keys like PATH or WINE
    final fullEnv = {...Platform.environment, ...baseEnv};
    
    // Create a shell instance specifically for Winetricks, ensuring it uses the correct environment
    // The verbose flag can be helpful for debugging Winetricks issues
    final winetricksShell = Shell(environment: fullEnv, verbose: true);

    // The existing setupShell for wineboot and winecfg is fine as it runs wineExecutablePath directly.
    final setupShell = Shell(environment: fullEnv, verbose: false);
    
    // Get an instance of PrefixManagementService for controller fix
    final prefixManagementService = PrefixManagementService(); 

    _logService.log('Initializing Wine prefix using build from $buildPath');

    if (!await File(effectiveWineExecutable).exists()) {
      final errorMsg = 'Could not find wine/proton executable at $effectiveWineExecutable';
      _logService.log(errorMsg, LogLevel.error);
      throw Exception(errorMsg);
    }
    _logService.log('Using wine executable: $effectiveWineExecutable');

    // Ensure it's executable
    try {
      await Shell(verbose: false).run('chmod +x "$effectiveWineExecutable"');
    } catch (e) {
      _logService.log('Warning: Could not set executable permission for $effectiveWineExecutable: $e', LogLevel.warning);
    }

    // Run wineboot -u for initialization
    onStatusUpdate('Running wineboot...');
    _logService.log('Running wineboot -u...');
    List<String> winebootArgs = [];
    if (isProton) winebootArgs.add('run');
    winebootArgs.addAll(['wineboot', '-u']);
    await setupShell.runExecutableArguments(effectiveWineExecutable, winebootArgs);

    // Set Windows version to win10
    onStatusUpdate('Setting Windows version to win10...');
    _logService.log('Running winecfg /v win10...');
    List<String> winecfgArgs = [];
    if (isProton) winecfgArgs.add('run');
    winecfgArgs.addAll(['winecfg', '/v', 'win10']);
    await setupShell.runExecutableArguments(effectiveWineExecutable, winecfgArgs);
    _logService.log('Windows version set to win10.');

    // Install core dependencies
    // Standard dependencies first
    final List<String> winetricksDeps = [
      // Core fonts to match Jeff Minter profile (arial32, times32, courie32)
      'arial',
      'courier',
      'times',
      // Other essential dependencies
      'd3dx9', // Common for older games
      'd3dcompiler_43', // For shader compilation
      // d3dcompiler_47 is also a gaming dependency, will be installed below if 64-bit
      'msls31', // Microsoft Line Services, sometimes needed
    ];

    onStatusUpdate('Installing core Winetricks components...');
    for (final dep in winetricksDeps) {
      onStatusUpdate('Installing $dep...');
      _logService.log('Installing winetricks $dep using WINE: $effectiveWineExecutable and WINEPREFIX: $prefixPath');
      try {
        // Use the winetricksShell with the correct environment for winetricks
        final results = await winetricksShell.run(
          'winetricks -q $dep',
        );
        final result = results.first; // Assuming single command, take the first result
        _logService.log('$dep installation finished. ${result.outText}');
        if (result.exitCode != 0) {
          _logService.log('Winetricks $dep installation failed with exit code ${result.exitCode}: ${result.errText}', LogLevel.warning);
          onStatusUpdate('Warning: $dep installation failed.');
        }
      } catch (e) {
        _logService.log('Error installing $dep with winetricks: $e', LogLevel.error);
        onStatusUpdate('Error installing $dep.');
      }
    }
    _logService.log('Core Winetricks components installation attempt finished.');

    // Install gaming-specific dependencies
    if (architecture == 'win64') {
      _logService.log('Attempting to install gaming dependencies for 64-bit prefix...');
      onStatusUpdate('Installing gaming dependencies (DXVK, VKD3D, VC++ Runtimes, etc.)...');

      final tempPrefix = WinePrefix(
          name: path.basename(prefixPath),
          path: prefixPath,
          wineBuildPath: buildPath,
          type: PrefixType.wine,
          architecture: architecture,
          exeEntries: [],
      );

      try {
        onStatusUpdate('Installing DXVK...');
        await _componentInstaller.installDxvk(tempPrefix, settings, customWineExecutable: effectiveWineExecutable, customEnv: fullEnv);
        _logService.log('DXVK installation attempt finished.');
      } catch (e) {
        _logService.log('Error installing DXVK: $e', LogLevel.error);
        onStatusUpdate('Error installing DXVK.');
      }

      try {
        onStatusUpdate('Installing VKD3D-Proton...');
        await _componentInstaller.installVkd3d(tempPrefix, settings, customWineExecutable: effectiveWineExecutable, customEnv: fullEnv);
        _logService.log('VKD3D-Proton installation attempt finished.');
      } catch (e) {
        _logService.log('Error installing VKD3D-Proton: $e', LogLevel.error);
        onStatusUpdate('Error installing VKD3D-Proton.');
      }

      // Install Microsoft Visual C++ 2015-2022 Redistributable (x64)
      onStatusUpdate('Downloading and installing Microsoft Visual C++ Redistributable (x64)...');
      _logService.log('Downloading and installing Microsoft Visual C++ Redistributable (x64)...');
      const vcRedistUrl = 'https://aka.ms/vs/17/release/vc_redist.x64.exe';
      final tempDirForVcRedist = await Directory.systemTemp.createTemp('vcredist_');
      final vcRedistPath = path.join(tempDirForVcRedist.path, 'vc_redist.x64.exe');

      try {
        await _dio.download(vcRedistUrl, vcRedistPath, onReceiveProgress: (received, total) {
          if (total > 0) {
            final progressPercent = (received / total * 100).toStringAsFixed(1);
            onStatusUpdate('Downloading VC++ Redist: $progressPercent%');
          }
        });
        _logService.log('VC++ Redistributable downloaded to $vcRedistPath');

        onStatusUpdate('Installing VC++ Redistributable (this might take a moment)...');
        final vcInstallArgs = [vcRedistPath, '/install', '/passive', '/norestart'];
        final vcInstallResult = await winetricksShell.runExecutableArguments(effectiveWineExecutable, vcInstallArgs);

        if (vcInstallResult.exitCode == 0 || vcInstallResult.exitCode == 3010) {
          _logService.log('VC++ Redistributable (x64) installed successfully. Exit code: ${vcInstallResult.exitCode}');
          onStatusUpdate('VC++ Redistributable (x64) installed.');
        } else {
          _logService.log('VC++ Redistributable (x64) installation failed. Exit code: ${vcInstallResult.exitCode}\nStdOut: ${vcInstallResult.outText}\nStdErr: ${vcInstallResult.errText}', LogLevel.error);
          onStatusUpdate('Error: VC++ Redistributable (x64) installation failed.');
        }
      } catch (e) {
        _logService.log('Error downloading or installing VC++ Redistributable (x64): $e', LogLevel.error);
        onStatusUpdate('Error installing VC++ Redistributable (x64).');
      }

      // Install dinput8 after VC++ Redist and before other gaming Winetricks deps
      /*
      onStatusUpdate('Installing dinput8 (controller fix component)...');
      _logService.log('Installing winetricks dinput8 --force for controller compatibility using WINE: $effectiveWineExecutable and WINEPREFIX: $prefixPath');
      try {
        final dinput8Results = await winetricksShell.run(
          'winetricks -q --force dinput8',
        );
        final dinput8Result = dinput8Results.first;
        _logService.log('dinput8 --force installation finished. ${dinput8Result.outText}');
        if (dinput8Result.exitCode != 0) {
          _logService.log('Winetricks dinput8 --force installation failed with exit code ${dinput8Result.exitCode}: ${dinput8Result.errText}', LogLevel.warning);
          onStatusUpdate('Warning: dinput8 --force installation failed.');
        }
      } catch (e) {
        _logService.log('Error installing dinput8 --force with winetricks: $e', LogLevel.error);
        onStatusUpdate('Error installing dinput8 --force.');
      }
      */
      
      // Install other gaming-specific Winetricks dependencies
      final List<String> gamingWinetricksDeps = [
        'd3dcompiler_47', // Newer d3dcompiler
      ];
      
      onStatusUpdate('Installing other Winetricks components: ${gamingWinetricksDeps.join(", ")}...');
      for (final dep in gamingWinetricksDeps) {
        onStatusUpdate('Installing $dep (Winetricks)...');
        _logService.log('Installing winetricks $dep using WINE: $effectiveWineExecutable and WINEPREFIX: $prefixPath');
        try {
          final results = await winetricksShell.run(
            'winetricks -q $dep',
          );
          final result = results.first;
          _logService.log('$dep installation finished (Winetricks). ${result.outText}');
          if (result.exitCode != 0) {
            _logService.log('Winetricks $dep installation failed with exit code ${result.exitCode}: ${result.errText}', LogLevel.warning);
            onStatusUpdate('Warning: $dep (Winetricks) installation failed.');
          }
        } catch (e) {
          _logService.log('Error installing $dep with winetricks: $e', LogLevel.error);
          onStatusUpdate('Error installing $dep (Winetricks).');
        }
      }

      // Apply Controller Fix (XInput, XAudio - dinput8 is now installed earlier)
      onStatusUpdate('Applying controller fix (XInput, XAudio)...');
      await _prefixManagementService.applyControllerFix(
        tempPrefix,
        onStatusUpdate: onStatusUpdate,
        customWineExecutable: effectiveWineExecutable,
        customEnv: fullEnv,
      );
      _logService.log('Controller fix applied.');
      
    } else {
      // Install dependencies for 32-bit prefixes
      _logService.log('Installing dependencies for 32-bit prefix...');
      onStatusUpdate('Installing dependencies for 32-bit prefix...');

      final tempPrefix = WinePrefix(
          name: path.basename(prefixPath),
          path: prefixPath,
          wineBuildPath: buildPath,
          type: PrefixType.wine,
          architecture: architecture,
          exeEntries: [],
      );

      // Install Microsoft Visual C++ 2015-2022 Redistributable (x86) for 32-bit prefixes
      onStatusUpdate('Downloading and installing Microsoft Visual C++ Redistributable (x86)...');
      _logService.log('Downloading and installing Microsoft Visual C++ Redistributable (x86)...');
      const vcRedistUrl = 'https://aka.ms/vs/17/release/vc_redist.x86.exe';
      final tempDirForVcRedist = await Directory.systemTemp.createTemp('vcredist_x86_');
      final vcRedistPath = path.join(tempDirForVcRedist.path, 'vc_redist.x86.exe');

      try {
        await _dio.download(vcRedistUrl, vcRedistPath, onReceiveProgress: (received, total) {
          if (total > 0) {
            final progressPercent = (received / total * 100).toStringAsFixed(1);
            onStatusUpdate('Downloading VC++ Redist (x86): $progressPercent%');
          }
        });
        _logService.log('VC++ Redistributable (x86) downloaded to $vcRedistPath');

        onStatusUpdate('Installing VC++ Redistributable (x86) (this might take a moment)...');
        final vcInstallArgs = [vcRedistPath, '/install', '/passive', '/norestart'];
        final vcInstallResult = await winetricksShell.runExecutableArguments(effectiveWineExecutable, vcInstallArgs);

        if (vcInstallResult.exitCode == 0 || vcInstallResult.exitCode == 3010) {
          _logService.log('VC++ Redistributable (x86) installed successfully. Exit code: ${vcInstallResult.exitCode}');
          onStatusUpdate('VC++ Redistributable (x86) installed.');
        } else {
          _logService.log('VC++ Redistributable (x86) installation failed. Exit code: ${vcInstallResult.exitCode}\nStdOut: ${vcInstallResult.outText}\nStdErr: ${vcInstallResult.errText}', LogLevel.error);
          onStatusUpdate('Error: VC++ Redistributable (x86) installation failed.');
        }
      } catch (e) {
        _logService.log('Error downloading or installing VC++ Redistributable (x86): $e', LogLevel.error);
        onStatusUpdate('Error installing VC++ Redistributable (x86).');
      }

      // Apply Controller Fix for 32-bit prefixes as well
      onStatusUpdate('Applying controller fix...');
      await _prefixManagementService.applyControllerFix(
        tempPrefix,
        onStatusUpdate: onStatusUpdate,
        customWineExecutable: effectiveWineExecutable,
        customEnv: fullEnv,
      );
      _logService.log('Controller fix applied.');

      _logService.log('Standard dependencies and controller fix installed for 32-bit prefix. Gaming components like DXVK/VKD3D can be installed manually if needed.');
      onStatusUpdate('Standard dependencies and controller fix installed for 32-bit prefix.');
    }

    onStatusUpdate('Prefix initialization complete.');
    _logService.log('Prefix initialization complete.');
  }
} 