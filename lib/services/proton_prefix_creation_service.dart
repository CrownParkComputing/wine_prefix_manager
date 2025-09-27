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

/// Service for creating Proton prefixes.
/// Note: Only the two latest Proton versions are made available for selection
/// to limit choices and ensure better compatibility.
class ProtonPrefixCreationService {
  final Dio _dio = Dio();
  final Shell _shell = Shell(verbose: false);
  final LogService _logService = LogService();
  final WineComponentInstaller _componentInstaller = WineComponentInstaller();
  final PrefixManagementService _prefixManagementService = PrefixManagementService();

  // Add a field to track the selected build for directory organization
  BaseBuild? _lastSelectedBuild;

  Future<WinePrefix?> createProtonPrefix({
    required BaseBuild? selectedBuild,
    required String prefixName,
    required Settings settings,
    required String architecture,
    required StatusCallback onStatusUpdate,
    required ProgressCallback onProgressUpdate,
  }) async {
    // Store the selected build for use in _getPrefixPath
    _lastSelectedBuild = selectedBuild;
    
    onStatusUpdate('Starting Proton prefix creation for "$prefixName" ($architecture)...');
    _logService.log('Starting Proton prefix creation for "$prefixName" ($architecture)...');

    print('CREATE_PREFIX_DEBUG: (PRINT) [PROTON] selectedBuild.name = ${selectedBuild?.name}');
    print('CREATE_PREFIX_DEBUG: (PRINT) [PROTON] selectedBuild.downloadUrl = ${selectedBuild?.downloadUrl}');
    print('CREATE_PREFIX_DEBUG: (PRINT) [PROTON] selectedBuild.installPath = ${selectedBuild?.installPath}');

    if (selectedBuild == null) {
      onStatusUpdate('Error: A build must be selected for Proton prefixes.');
      _logService.log('Proton prefix creation failed: No build selected.', LogLevel.error);
      return null;
    }

    // Verify the build is a Proton build
    if (selectedBuild.type != PrefixType.proton) {
      final errorMsg = 'Error: Selected build type (${selectedBuild.type.name}) must be Proton for Proton prefix type.';
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
      final fileName = selectedBuild.name;
      final filePath = path.join(downloadDir, fileName);

      print('CREATE_PREFIX_DEBUG: (PRINT) [PROTON] downloadDir = $downloadDir');
      print('CREATE_PREFIX_DEBUG: (PRINT) [PROTON] fileName = $fileName');
      print('CREATE_PREFIX_DEBUG: (PRINT) [PROTON] filePath = $filePath');

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
      String extractedName = fileName;
      // Remove common archive extensions
      extractedName = extractedName.replaceAll('.tar.xz', '').replaceAll('.tar.gz', '').replaceAll('.tar.bz2', '').replaceAll('.tar.zst', '');
      extractedDir = path.join(downloadDir, extractedName);

      print('CREATE_PREFIX_DEBUG: (PRINT) [PROTON] extractedName = $extractedName');
      print('CREATE_PREFIX_DEBUG: (PRINT) [PROTON] (initial) extractedDir = $extractedDir');

      // Check if extraction is needed
      if (!await Directory(extractedDir).exists() || await Directory(extractedDir).list().isEmpty) {
        // Get a list of current directories to compare after extraction
        final List<FileSystemEntity> beforeDirs = await Directory(downloadDir)
            .list()
            .where((entity) => entity is Directory)
            .toList();

        _logService.log('Extracting "$filePath" to "$downloadDir"...');
        
        // Determine correct tar command based on file extension
        String tarCommand;
        if (filePath.toLowerCase().endsWith('.tar.xz')) {
          tarCommand = 'tar -xvf "$filePath" -C "$downloadDir"';
        } else {
          tarCommand = 'tar -xvf "$filePath" -C "$downloadDir"';
        }
        
        // Run tar with verbose mode to log extracted files
        final results = await _shell.run(tarCommand);
        String extractionOutput = results.first.stdout;
        _logService.log('Extraction output: $extractionOutput');
        onStatusUpdate('Extraction complete.');
        _logService.log('Extraction complete.');
        
        // Get list of directories after extraction and find new ones
        final List<FileSystemEntity> afterDirs = await Directory(downloadDir)
            .list()
            .where((entity) => entity is Directory)
            .toList();
        
        final List<FileSystemEntity> newDirs = afterDirs
            .where((after) => !beforeDirs.any((before) => before.path == after.path))
            .toList();
        
        // If new directory is found, use that as the extracted directory
        if (newDirs.isNotEmpty) {
          extractedDir = newDirs.first.path;
          _logService.log('Found new extracted directory: $extractedDir');
        } else {
          // Try to determine directory name from the extraction output
          final RegExp dirRegex = RegExp(r'^([^/]+)/');
          final Match? match = dirRegex.firstMatch(extractionOutput.split('\n').firstWhere(
            (line) => line.contains('/'), 
            orElse: () => ''
          ));
          
          if (match != null && match.groupCount >= 1) {
            final String detectedDirName = match.group(1) ?? '';
            if (detectedDirName.isNotEmpty) {
              extractedDir = path.join(downloadDir, detectedDirName);
              _logService.log('Detected directory from extraction output: $extractedDir');
            }
          }
        }
        
        // Check what was extracted
        if (await Directory(extractedDir).exists()) {
          final contents = await Directory(extractedDir).list().toList();
          _logService.log('Extracted contents: ${contents.map((e) => e.path).join(', ')}');
        } else {
          _logService.log('Could not find extracted directory at $extractedDir');
          
          // Last resort: look for any directory containing "proton" in the name
          final List<FileSystemEntity> protonDirs = afterDirs
              .where((dir) => path.basename(dir.path).toLowerCase().contains('proton'))
              .toList();
          
          if (protonDirs.isNotEmpty) {
            extractedDir = protonDirs.first.path;
            _logService.log('Found proton directory: $extractedDir');
          }
        }
      } else {
        onStatusUpdate('Build already extracted.');
        _logService.log('Build already extracted at $extractedDir.');
        // List contents of the directory
        final contents = await Directory(extractedDir).list().toList();
        _logService.log('Directory contents: ${contents.map((e) => e.path).join(', ')}');
      }

      if (!await Directory(extractedDir).exists()) {
        // Try with wine-proton prefix for Kronek builds
        if (selectedBuild.name.contains('Kronek')) {
          String altExtractedDir = path.join(downloadDir, 'wine-proton-${extractedName.split('-').last}');
          if (await Directory(altExtractedDir).exists()) {
            extractedDir = altExtractedDir;
            _logService.log('Found Kronek Proton at alternate path: $extractedDir');
          } else {
            final errorMsg = 'Extraction failed: Directory "$extractedDir" not found after extraction attempt.';
            _logService.log(errorMsg, LogLevel.error);
            throw Exception(errorMsg);
          }
        } else {
          final errorMsg = 'Extraction failed: Directory "$extractedDir" not found after extraction attempt.';
          _logService.log(errorMsg, LogLevel.error);
          throw Exception(errorMsg);
        }
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
        'type': PrefixType.proton.toString(),
        'architecture': architecture,
      }));
      _logService.log('Prefix config saved.');

      // 5. Initialize Prefix
      onStatusUpdate('Initializing prefix ($architecture, this might take a moment)...');
      print('CREATE_PREFIX_DEBUG: (PRINT) [PROTON] Calling _initializeProtonPrefix with buildPath = $extractedDir');
      await _initializeProtonPrefix(prefixPath, extractedDir, architecture, settings, onStatusUpdate, selectedBuild);
      _logService.log('Proton prefix initialized.');

      onStatusUpdate('Proton prefix "$prefixName" ($architecture) created successfully!');
      _logService.log('Proton prefix "$prefixName" ($architecture) created successfully!');

      // 6. Return new WinePrefix object
      return WinePrefix(
        name: prefixName,
        path: prefixPath,
        wineBuildPath: extractedDir,
        type: PrefixType.proton,
        architecture: architecture,
        exeEntries: [],
      );

    } catch (e, stackTrace) {
      _logService.log('Error creating Proton prefix "$prefixName": $e\n$stackTrace', LogLevel.error);
      onStatusUpdate('Error creating Proton prefix "$prefixName": $e');
      return null;
    }
  }

  Future<String> _getDownloadDirectory() async {
    const String appName = 'wine_prefix_manager';
    const String buildsSubDir = 'downloaded_builds'; // Consistent subdirectory
    final homeDir = Platform.environment['HOME'];

    String baseDir;

    if (homeDir != null && homeDir.isNotEmpty) {
      // Preferred: User's local share directory
      baseDir = path.join(homeDir, '.local', 'share', appName, buildsSubDir);
    } else {
      // Fallback: System's temporary directory
      _logService.log('HOME environment variable not set. Using temporary directory for Proton downloads.', LogLevel.warning);
      final tempDir = await Directory.systemTemp.createTemp('${appName}_proton_downloads_');
      baseDir = tempDir.path;
    }
    
    // Ensure the directory exists
    try {
      final dir = Directory(baseDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        _logService.log('Created Proton download directory: $baseDir');
      }
    } catch (e) {
      _logService.log('Error creating Proton download directory $baseDir: $e', LogLevel.error);
      final tempDir = await Directory.systemTemp.createTemp('wpm_proton_dl_fallback_');
      return tempDir.path;
    }

    _logService.log('Using Proton download directory: $baseDir');
    return baseDir;
  }

  String _getPrefixPath(Settings settings, String prefixName) {
    final homeDir = Platform.environment['HOME'];
    // Initialize with a fallback to ensure it's always assigned.
    String baseDirToUse = path.join(Directory.systemTemp.path, 'wine_prefix_manager', 'prefixes');
    _logService.log('Initial fallback for Proton baseDirToUse: $baseDirToUse (will be overridden by preferred paths if available)', LogLevel.debug);

    bool useCustomPath = false;

    // Priority 1: User-defined absolute path in settings
    if (settings.prefixDirectory.isNotEmpty) {
      if (path.isAbsolute(settings.prefixDirectory)) {
        String userDefinedPath = settings.prefixDirectory;
        try {
          final dir = Directory(userDefinedPath);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
            _logService.log('Created user-specified absolute prefix directory for Proton: $userDefinedPath');
          }
          baseDirToUse = userDefinedPath;
          useCustomPath = true;
          _logService.log('Using user-defined absolute prefix directory for Proton: $baseDirToUse');
        } catch (e) {
          _logService.log('Error creating/accessing user-specified absolute prefix directory $userDefinedPath for Proton: $e. Falling back.', LogLevel.error);
          // useCustomPath remains false
        }
      } else {
        _logService.log('Warning: settings.prefixDirectory ("${settings.prefixDirectory}") is not absolute. Using default app data location for Proton prefixes.', LogLevel.warning);
      }
    }

    // Priority 2: Fallback to default if custom path not used or failed
    if (!useCustomPath) {
        if (homeDir != null && homeDir.isNotEmpty) {
            baseDirToUse = path.join(homeDir, '.local', 'share', 'wine_prefix_manager', 'prefixes');
            _logService.log('Using default app data directory for Proton prefixes: $baseDirToUse');
        } else {
            _logService.log('Warning: HOME environment variable not set. Using temporary directory for Proton prefixes (already set as initial fallback): $baseDirToUse', LogLevel.warning);
             // baseDirToUse is already set to the temp path
        }
    }
    
    // Ensure the final chosen base directory exists
    try {
      final dir = Directory(baseDirToUse);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
        _logService.log('Ensured final base Proton prefix directory exists: $baseDirToUse');
      }
    } catch (e) {
      _logService.log('Critical Error: Could not create final base Proton prefix directory $baseDirToUse: $e.', LogLevel.error);
      throw Exception('Failed to create final base Proton prefix directory: $baseDirToUse. Error: $e');
    }

    // Create the type-specific subfolder based on the specific Proton build source
    String typeDir;
    if (_lastSelectedBuild != null) {
      if (_lastSelectedBuild!.name.contains('GE-Proton')) {
        typeDir = path.join(baseDirToUse, 'proton-ge');
      } else if (_lastSelectedBuild!.name.contains('Kronek') || _lastSelectedBuild!.name.contains('wine-proton')) {
        typeDir = path.join(baseDirToUse, 'proton-kronek');
      } else {
        typeDir = path.join(baseDirToUse, 'proton'); // Generic proton
      }
    } else {
      typeDir = path.join(baseDirToUse, 'proton'); // Fallback if build not known
    }
    
    try {
        Directory(typeDir).createSync(recursive: true);
    } catch (e) {
        _logService.log('Critical Error: Could not create type-specific Proton prefix directory $typeDir: $e.', LogLevel.error);
        throw Exception('Failed to create type-specific Proton prefix directory: $typeDir. Error: $e');
    }

    _logService.log('Final Proton prefix path for "$prefixName" will be under: $typeDir');
    return path.join(typeDir, prefixName);
  }

  Future<void> _initializeProtonPrefix(
    String prefixPath, 
    String buildPath, 
    String architecture,
    Settings settings, 
    StatusCallback onStatusUpdate,
    BaseBuild? selectedBuild
  ) async {
    print('INIT_PREFIX_DEBUG: (PRINT) [PROTON] Received buildPath = $buildPath');
    
    _logService.log('Initializing Proton prefix at $prefixPath using build from $buildPath');

    // Find the Proton run script (e.g., proton, wine, or a specific script)
    String protonRunScript = await _findProtonRunScript(buildPath);
    print('INIT_PREFIX_DEBUG: (PRINT) [PROTON] Found protonRunScript = $protonRunScript');
    
    _logService.log('Using Proton run script: $protonRunScript');

    // Ensure it's executable
    try {
      await Shell(verbose: false).run('chmod +x "$protonRunScript"');
    } catch (e) {
      _logService.log('Warning: Could not set executable permission for Proton run script: $e', LogLevel.warning);
    }

    // Set up environment variables for Proton
    // These are often crucial for Proton to function correctly
    final Map<String, String> protonEnv = {
      'WINEPREFIX': prefixPath,
      'STEAM_COMPAT_DATA_PATH': prefixPath, // Proton uses this to find the prefix
      'STEAM_COMPAT_CLIENT_INSTALL_PATH': Platform.environment['HOME'] ?? '/tmp', // Dummy Steam path
      'PROTON_LOG': '1', // Enable Proton logging by default for easier troubleshooting
      'PATH': '$buildPath/bin:$buildPath/files/bin:${Platform.environment['PATH']}', // Common Proton bin locations
      'LD_LIBRARY_PATH': '$buildPath/lib64:$buildPath/lib:$buildPath/files/lib64:$buildPath/files/lib:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
      'WINEDLLOVERRIDES': 'winemenubuilder.exe=d', // Disable wine menu builder
      // Add other common Proton variables if necessary, e.g., PROTON_ENABLE_NVAPI, PROTON_USE_WINED3D etc.
      // For now, keeping it minimal, specific game configs can add more.
    };
    final fullEnv = {...Platform.environment, ...protonEnv};
    final setupShell = Shell(environment: fullEnv, verbose: false);

    onStatusUpdate('Running wineboot via Proton (this may take a moment)...');
    _logService.log('Executing wineboot -u with Proton...');
    
    // Determine if this is a true Proton script or a Wine executable
    final isWineExecutable = protonRunScript.endsWith('/wine') || protonRunScript.endsWith('/wine64');
    
    ProcessResult result;
    if (isWineExecutable) {
      // For Wine executables, don't use 'run' prefix
      final winebootArgs = ['wineboot', '-u'];
      result = await setupShell.runExecutableArguments(protonRunScript, winebootArgs);
    } else {
      // For true Proton scripts, use 'run' prefix
      final winebootArgs = ['run', 'wineboot', '-u'];
      result = await setupShell.runExecutableArguments(protonRunScript, winebootArgs);
    }
    _logService.log('Proton wineboot finished. stdout: ${result.stdout}, stderr: ${result.stderr}');

    onStatusUpdate('Setting Windows version to win10 via Proton...');
    _logService.log('Executing winecfg /v win10 with Proton...');
    
    if (isWineExecutable) {
      // For Wine executables, don't use 'run' prefix
      final winecfgArgs = ['winecfg', '/v', 'win10'];
      result = await setupShell.runExecutableArguments(protonRunScript, winecfgArgs);
    } else {
      // For true Proton scripts, use 'run' prefix
      final winecfgArgs = ['run', 'winecfg', '/v', 'win10'];
      result = await setupShell.runExecutableArguments(protonRunScript, winecfgArgs);
    }
    _logService.log('Proton winecfg finished. stdout: ${result.stdout}, stderr: ${result.stderr}');

    _logService.log('Proton prefix core initialization complete.');
    onStatusUpdate('Proton prefix core initialization complete.');

    // Install core Winetricks components needed for Proton environments
    final List<String> winetricksDeps = [
      'corefonts',
      'd3dx9',
      'd3dcompiler_43',
      // d3dcompiler_47 and vcrun2019 will be installed next for 64-bit
      'msls31',
      // Mono and Gecko are often handled by Proton itself or less critical
    ];

    onStatusUpdate('Installing core Winetricks components for Proton...');
    for (final dep in winetricksDeps) {
      onStatusUpdate('Installing $dep (Winetricks)...');
      _logService.log('Installing winetricks $dep for Proton prefix...');
      try {
        if (isWineExecutable) {
          // For Wine executables, set WINE env var and run winetricks directly
          final winetricksShell = Shell(environment: {...fullEnv, 'WINE': protonRunScript}, verbose: false);
          final wtResults = await winetricksShell.run('winetricks -q $dep');
          final wtResult = wtResults.first;
          _logService.log('$dep installation finished (Winetricks). stdout: ${wtResult.stdout}, stderr: ${wtResult.stderr}');
          if (wtResult.exitCode != 0) {
            _logService.log('Winetricks $dep installation failed with exit code ${wtResult.exitCode}: ${wtResult.stderr}', LogLevel.warning);
            onStatusUpdate('Warning: $dep (Winetricks) installation failed.');
          }
        } else {
          // For true Proton scripts, run via the script
          final wtResults = await setupShell.run('"$protonRunScript" run winetricks -q $dep');
          final wtResult = wtResults.first;
          _logService.log('$dep installation finished (Winetricks). stdout: ${wtResult.stdout}, stderr: ${wtResult.stderr}');
          if (wtResult.exitCode != 0) {
            _logService.log('Winetricks $dep installation failed with exit code ${wtResult.exitCode}: ${wtResult.stderr}', LogLevel.warning);
            onStatusUpdate('Warning: $dep (Winetricks) installation failed.');
          }
        }
      } catch (e) {
        _logService.log('Error installing $dep with winetricks for Proton: $e', LogLevel.error);
        onStatusUpdate('Error installing $dep (Winetricks).');
      }
    }
    _logService.log('Core Winetricks components installation attempt for Proton finished.');

    // Install gaming-specific dependencies for 64-bit Proton prefixes
    // Assume win64 for Proton prefixes as they are primarily for gaming.
    _logService.log('Attempting to install gaming dependencies for 64-bit Proton prefix...');
    onStatusUpdate('Installing gaming dependencies (DXVK, VKD3D, etc.) for Proton...');

    if (architecture == 'win64') { // Double check, though it should always be for Proton
      _logService.log('Attempting to install common dependencies for Proton prefix (win64 assumed)...');
      onStatusUpdate('Installing common dependencies (vcrun, controller fix, etc.)...');

      final tempPrefix = WinePrefix(
        name: path.basename(prefixPath),
        path: prefixPath,
        wineBuildPath: buildPath, // This is the Proton build path
        type: PrefixType.proton,
        architecture: architecture,
        exeEntries: [], 
      );

      // For Kronek builds, use the same installation method as regular Wine prefixes
      final isKronekBuild = buildPath.contains('wine-proton') || buildPath.contains('kronek');
      final isProtonGE = buildPath.contains('GE-Proton') || (selectedBuild?.name.contains('GE-Proton') ?? false);
      
      if (isKronekBuild) {
        _logService.log('Kronek Proton build detected - installing DXVK, VKD3D, and VC++ Redistributable using standard Wine methods.');
        onStatusUpdate('Installing DXVK, VKD3D, and VC++ Redistributable for Kronek Proton...');
        
        try {
          onStatusUpdate('Installing DXVK...');
          await _componentInstaller.installDxvk(tempPrefix, settings, customWineExecutable: protonRunScript, customEnv: protonEnv);
          _logService.log('DXVK installation attempt finished.');
        } catch (e) {
          _logService.log('Error installing DXVK: $e', LogLevel.error);
          onStatusUpdate('Error installing DXVK.');
        }

        try {
          onStatusUpdate('Installing VKD3D-Proton...');
          await _componentInstaller.installVkd3d(tempPrefix, settings, customWineExecutable: protonRunScript, customEnv: protonEnv);
          _logService.log('VKD3D-Proton installation attempt finished.');
        } catch (e) {
          _logService.log('Error installing VKD3D-Proton: $e', LogLevel.error);
          onStatusUpdate('Error installing VKD3D-Proton.');
        }

        // Install Microsoft Visual C++ 2015-2022 Redistributable (x64) - same as regular Wine
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
          final vcInstallResult = await setupShell.runExecutableArguments(protonRunScript, vcInstallArgs);

          if (vcInstallResult.exitCode == 0 || vcInstallResult.exitCode == 3010) {
            _logService.log('VC++ Redistributable (x64) installed successfully. Exit code: ${vcInstallResult.exitCode}');
            onStatusUpdate('VC++ Redistributable (x64) installed.');
          } else {
            _logService.log('VC++ Redistributable (x64) installation failed. Exit code: ${vcInstallResult.exitCode}\nStdOut: ${vcInstallResult.stdout}\nStdErr: ${vcInstallResult.stderr}', LogLevel.error);
            onStatusUpdate('Error: VC++ Redistributable (x64) installation failed.');
          }
        } catch (e) {
          _logService.log('Error downloading or installing VC++ Redistributable (x64): $e', LogLevel.error);
          onStatusUpdate('Error installing VC++ Redistributable (x64).');
        }

        // Install d3dcompiler_47 via winetricks
        onStatusUpdate('Installing d3dcompiler_47 (Winetricks)...');
        _logService.log('Installing winetricks d3dcompiler_47 for Kronek Proton prefix...');
        try {
          if (isWineExecutable) {
            final winetricksShell = Shell(environment: {...fullEnv, 'WINE': protonRunScript}, verbose: false);
            final wtResults = await winetricksShell.run('winetricks -q d3dcompiler_47');
            final wtResult = wtResults.first;
            _logService.log('d3dcompiler_47 installation finished (Winetricks). stdout: ${wtResult.stdout}, stderr: ${wtResult.stderr}');
            if (wtResult.exitCode != 0) {
              _logService.log('Winetricks d3dcompiler_47 installation failed with exit code ${wtResult.exitCode}: ${wtResult.stderr}', LogLevel.warning);
              onStatusUpdate('Warning: d3dcompiler_47 (Winetricks) installation failed.');
            }
          } else {
            final wtResults = await setupShell.run('"$protonRunScript" run winetricks -q d3dcompiler_47');
            final wtResult = wtResults.first;
            _logService.log('d3dcompiler_47 installation finished (Winetricks). stdout: ${wtResult.stdout}, stderr: ${wtResult.stderr}');
            if (wtResult.exitCode != 0) {
              _logService.log('Winetricks d3dcompiler_47 installation failed with exit code ${wtResult.exitCode}: ${wtResult.stderr}', LogLevel.warning);
              onStatusUpdate('Warning: d3dcompiler_47 (Winetricks) installation failed.');
            }
          }
        } catch (e) {
          _logService.log('Error installing d3dcompiler_47 with winetricks: $e', LogLevel.error);
          onStatusUpdate('Error installing d3dcompiler_47 (Winetricks).');
        }
      } else if (isProtonGE) {
        // For Proton-GE builds, only install VC++ runtime - everything else is included
        _logService.log('Proton-GE build detected - only installing VC++ Redistributable (other components are built-in).');
        onStatusUpdate('Installing VC++ Redistributable for Proton-GE...');

        // Install Microsoft Visual C++ 2015-2022 Redistributable (x64)
        onStatusUpdate('Downloading and installing Microsoft Visual C++ Redistributable (x64)...');
        _logService.log('Downloading and installing Microsoft Visual C++ Redistributable (x64) for Proton-GE...');
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
          final vcInstallResult = await setupShell.runExecutableArguments(protonRunScript, vcInstallArgs);

          if (vcInstallResult.exitCode == 0 || vcInstallResult.exitCode == 3010) {
            _logService.log('VC++ Redistributable (x64) installed successfully for Proton-GE. Exit code: ${vcInstallResult.exitCode}');
            onStatusUpdate('VC++ Redistributable (x64) installed.');
          } else {
            _logService.log('VC++ Redistributable (x64) installation failed for Proton-GE. Exit code: ${vcInstallResult.exitCode}\nStdOut: ${vcInstallResult.stdout}\nStdErr: ${vcInstallResult.stderr}', LogLevel.error);
            onStatusUpdate('Error: VC++ Redistributable (x64) installation failed.');
          }
        } catch (e) {
          _logService.log('Error downloading or installing VC++ Redistributable (x64) for Proton-GE: $e', LogLevel.error);
          onStatusUpdate('Error installing VC++ Redistributable (x64).');
        }

        _logService.log('VC++ Redistributable installation completed for Proton-GE.');
      } else {
        // Minimal 32-bit Proton prefix setup with proper configuration
        _logService.log('32-bit Proton prefix detected - setting up with proper win32 architecture...');
        onStatusUpdate('Configuring 32-bit Proton prefix...');

        // Set Windows version to win10 for 32-bit Proton prefix
        onStatusUpdate('Setting Windows version to win10 for 32-bit Proton prefix...');
        _logService.log('Running winecfg /v win10 for 32-bit Proton prefix...');
        List<String> winecfgArgs = [];
        
        if (isWineExecutable) {
          // For Wine executables, don't use 'run' prefix
          winecfgArgs.addAll(['winecfg', '/v', 'win10']);
        } else {
          // For true Proton scripts, use 'run' prefix
          winecfgArgs.addAll(['run', 'winecfg', '/v', 'win10']);
        }
        
        try {
          await setupShell.runExecutableArguments(protonRunScript, winecfgArgs);
          _logService.log('Windows version set to win10 for 32-bit Proton prefix.');
          onStatusUpdate('Windows version configured for 32-bit Proton prefix.');
        } catch (e) {
          _logService.log('Warning: Could not set Windows version for 32-bit Proton prefix: $e', LogLevel.warning);
          onStatusUpdate('Warning: Windows version setting failed, but prefix should still work.');
        }

        _logService.log('32-bit Proton prefix setup complete with proper architecture configuration.');
        onStatusUpdate('32-bit Proton prefix created successfully! Ready for 32-bit applications.');
      }
    } else {
      // Completely minimal 32-bit Proton prefix setup - bare prefix only
      _logService.log('Creating completely minimal 32-bit Proton prefix - bare prefix only...');
      onStatusUpdate('Creating minimal 32-bit Proton prefix...');

      _logService.log('32-bit Proton prefix setup complete - bare prefix ready for manual configuration.');
      onStatusUpdate('32-bit Proton prefix created successfully! Install VC++ and configure manually via winecfg button as needed.');
    }

    _logService.log('Gaming dependencies installation attempt for Proton finished.');
    onStatusUpdate('Gaming dependencies installation for Proton complete.');

    onStatusUpdate('Prefix initialization complete.');
    _logService.log('Prefix initialization complete.');
  }

  Future<String> _findProtonRunScript(String buildPath) async {
    // First, try to find the standard Proton script
    final protonScript = path.join(buildPath, 'proton');
    if (await File(protonScript).exists()) {
      return protonScript;
    }

    // Try proton.sh as alternative
    final protonShScript = path.join(buildPath, 'proton.sh');
    if (await File(protonShScript).exists()) {
      return protonShScript;
    }

    // For Kronek/Wine-Proton builds, they use standard Wine executables
    // Check for wine executable in bin directory
    final wineExecutable = path.join(buildPath, 'bin', 'wine');
    if (await File(wineExecutable).exists()) {
      _logService.log('Kronek Wine-Proton build detected - using wine executable instead of proton script');
      return wineExecutable;
    }

    // If none found, throw an error
    throw Exception('No Proton script or Wine executable found in $buildPath');
  }
} 