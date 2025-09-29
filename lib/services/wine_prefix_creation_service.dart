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

    // Early check for 32-bit prefix requests with WoW64-only builds
    if (architecture == 'win32') {
      _logService.log('32-bit prefix requested - checking Wine build compatibility...');
      onStatusUpdate('Checking Wine build compatibility for 32-bit prefix...');
      
      final isWoW64Only = await _checkIfWoW64Only(selectedBuild);
      if (isWoW64Only) {
        const errorMsg = 'This Wine build only supports 64-bit prefixes (WoW64 mode). However, 64-bit prefixes can run both 32-bit and 64-bit applications automatically. Please create a 64-bit prefix instead.';
        _logService.log(errorMsg, LogLevel.error);
        onStatusUpdate('Error: Wine build requires 64-bit prefix for 32-bit app compatibility');
        throw Exception(errorMsg);
      }
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
    const String appName = 'wine_prefix_manager';
    const String buildsSubDir = 'downloaded_builds';
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

    // For 32-bit prefixes, check if Wine build supports them (WoW64 builds don't)
    if (architecture == 'win32') {
      _logService.log('32-bit prefix detected - setting up with proper win32 architecture...');
      onStatusUpdate('Configuring 32-bit prefix...');

      // Open winecfg for user to select Windows version (optional - may fail in some environments)
      onStatusUpdate('Attempting to open winecfg for Windows version selection...');
      _logService.log('Attempting to open winecfg for user to configure Windows version...');
      _logService.log('Environment: WINEPREFIX=$prefixPath, WINEARCH=$architecture');
      _logService.log('Wine executable: $effectiveWineExecutable');
      _logService.log('Display environment: DISPLAY=${Platform.environment['DISPLAY']}, WAYLAND_DISPLAY=${Platform.environment['WAYLAND_DISPLAY']}');
      
      List<String> winecfgArgs = [];
      if (isProton) winecfgArgs.add('run');
      winecfgArgs.add('winecfg');
      
      try {
        _logService.log('Executing: $effectiveWineExecutable ${winecfgArgs.join(' ')}');
        final result = await setupShell.runExecutableArguments(effectiveWineExecutable, winecfgArgs);
        _logService.log('winecfg result: exit code ${result.exitCode}');
        _logService.log('winecfg stdout: ${result.stdout}');
        _logService.log('winecfg stderr: ${result.stderr}');
        
        if (result.exitCode == 0) {
          _logService.log('winecfg completed successfully for 32-bit prefix configuration.');
          onStatusUpdate('winecfg completed successfully. Windows version configured.');
        } else {
          _logService.log('winecfg finished with exit code ${result.exitCode}', LogLevel.warning);
          onStatusUpdate('winecfg exited with issues. You can configure it manually later via the winecfg button.');
        }
      } catch (e) {
        _logService.log('Error opening winecfg for 32-bit prefix: $e', LogLevel.error);
        onStatusUpdate('winecfg could not open (display issue?). Use the winecfg button to configure manually.');
      }

      _logService.log('32-bit prefix setup complete with user-selected configuration.');
      onStatusUpdate('32-bit prefix created successfully! Ready for 32-bit applications.');
    } else {
      // Full setup for 64-bit prefixes
      _logService.log('64-bit prefix detected - proceeding with full gaming setup...');
      onStatusUpdate('Setting up 64-bit prefix with gaming components...');

      // Set Windows version to win10 (only for 64-bit)
      onStatusUpdate('Setting Windows version to win10...');
      _logService.log('Running winecfg /v win10...');
      List<String> winecfgArgs = [];
      if (isProton) winecfgArgs.add('run');
      winecfgArgs.addAll(['winecfg', '/v', 'win10']);
      await setupShell.runExecutableArguments(effectiveWineExecutable, winecfgArgs);
      _logService.log('Windows version set to win10.');

      // Install core dependencies (only for 64-bit)
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

      // Full gaming setup for 64-bit prefixes
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

      // Install comprehensive Microsoft Visual C++ Redistributables (2015-2022 x64 and x86)
      onStatusUpdate('Installing comprehensive Visual C++ Redistributables...');
      _logService.log('Installing comprehensive VC++ redistributables with registry entries...');
      
      try {
        final vcInstallSuccess = await _componentInstaller.installAllVcppRedistributablesComprehensive(
          tempPrefix, 
          settings, 
          progressCallback: onStatusUpdate,
          customWineExecutable: effectiveWineExecutable, 
          customEnv: fullEnv
        );
        
        if (vcInstallSuccess) {
          _logService.log('Comprehensive VC++ redistributables installed successfully');
          onStatusUpdate('Visual C++ Redistributables (x64 & x86) installed with registry entries.');
        } else {
          _logService.log('Comprehensive VC++ redistributables installation failed', LogLevel.error);
          onStatusUpdate('Warning: VC++ redistributables installation failed.');
        }
      } catch (e) {
        _logService.log('Error installing comprehensive VC++ redistributables: $e', LogLevel.error);
        onStatusUpdate('Error installing VC++ redistributables.');
      }

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

      // Apply Controller Fix (XInput, XAudio)
      onStatusUpdate('Applying controller fix (XInput, XAudio)...');
      await _prefixManagementService.applyControllerFix(
        tempPrefix,
        onStatusUpdate: onStatusUpdate,
        customWineExecutable: effectiveWineExecutable,
        customEnv: fullEnv,
      );
      _logService.log('Controller fix applied.');
    }

    onStatusUpdate('Prefix initialization complete.');
    _logService.log('Prefix initialization complete.');
  }

  Future<bool> _checkIfWoW64Only(BaseBuild selectedBuild) async {
    try {
      // For downloadable builds, we need to check the actual Wine executable
      // For now, assume system Wine (which we know is WoW64-only based on test results)
      
      // Quick test: try to create a temporary 32-bit prefix
      final tempTestPrefix = path.join(Directory.systemTemp.path, 'wine_wow64_test_${DateTime.now().millisecondsSinceEpoch}');
      
      // Set up test environment
      final testEnv = {
        'WINEPREFIX': tempTestPrefix,
        'WINEARCH': 'win32',
        'WINEDLLOVERRIDES': 'winemenubuilder.exe=d',
      };

      _logService.log('Testing for WoW64-only mode with temporary prefix: $tempTestPrefix');
      
      // For system Wine (when selectedBuild has no downloadUrl), test directly
      if (selectedBuild.downloadUrl == null && selectedBuild.installPath == null) {
        final testResults = await Shell(environment: testEnv, verbose: false)
            .run('wine wineboot --init');
        final testResult = testResults.first; // Get the first (and only) result
        
        // Clean up test prefix regardless of result
        try {
          if (Directory(tempTestPrefix).existsSync()) {
            Directory(tempTestPrefix).deleteSync(recursive: true);
          }
        } catch (e) {
          _logService.log('Could not clean up WoW64 test prefix: $e', LogLevel.warning);
        }

        // Check if the error indicates WoW64-only mode
        if (testResult.exitCode != 0 && testResult.stderr.contains('wow64 mode')) {
          _logService.log('Detected WoW64-only Wine build - 32-bit prefixes not supported');
          return true;
        }
        
        _logService.log('Wine build supports true 32-bit prefixes');
        return false;
      }
      
      // For downloadable builds, we'll assume they support 32-bit unless proven otherwise
      // TODO: Could be enhanced to check the actual build characteristics
      _logService.log('Downloadable Wine build - assuming 32-bit prefix support');
      return false;
      
    } catch (e) {
      _logService.log('Error checking WoW64 mode: $e', LogLevel.warning);
      // If we can't determine, assume it supports 32-bit and let the user find out
      return false;
    }
  }
} 