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

typedef StatusCallback = void Function(String status);
typedef ProgressCallback = void Function(double progress);

class WinePrefixCreationService {
  final Dio _dio = Dio();
  final Shell _shell = Shell(verbose: false);
  final LogService _logService = LogService();
  final WineComponentInstaller _componentInstaller = WineComponentInstaller();

  Future<WinePrefix?> createWinePrefix({
    required BaseBuild? selectedBuild,
    required String prefixName,
    required Settings settings,
    required StatusCallback onStatusUpdate,
    required ProgressCallback onProgressUpdate,
  }) async {
    onStatusUpdate('Starting Wine prefix creation for "$prefixName"...');
    _logService.log('Starting Wine prefix creation for "$prefixName"...');

    if (selectedBuild == null) {
      onStatusUpdate('Error: A build must be selected for Wine prefixes.');
      _logService.log('Wine prefix creation failed: No build selected.', LogLevel.error);
      return null;
    }

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
      final fileName = selectedBuild.name;
      final filePath = path.join(downloadDir, fileName);

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
      final extractedName = fileName.replaceAll('.tar.xz', '');
      extractedDir = path.join(downloadDir, extractedName);

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

      // 3. Create Prefix Directory
      onStatusUpdate('Creating prefix directory...');
      String prefixPath = _getPrefixPath(settings, prefixName);
      await Directory(prefixPath).create(recursive: true);
      _logService.log('Prefix directory created at: $prefixPath');

      // 4. Save Prefix Config
      final configFile = File(path.join(prefixPath, '.prefix_config'));
      await configFile.writeAsString(jsonEncode({
        'buildPath': extractedDir,
        'type': PrefixType.wine.toString()
      }));
      _logService.log('Prefix config saved.');

      // 5. Initialize Prefix
      onStatusUpdate('Initializing prefix (this might take a moment)...');
      await _initializeWinePrefix(prefixPath, extractedDir, settings, onStatusUpdate);
      _logService.log('Wine prefix initialized.');

      onStatusUpdate('Wine prefix "$prefixName" created successfully!');
      _logService.log('Wine prefix "$prefixName" created successfully!');

      // 6. Return new WinePrefix object
      return WinePrefix(
        name: prefixName,
        path: prefixPath,
        wineBuildPath: extractedDir,
        type: PrefixType.wine,
        exeEntries: [],
      );

    } catch (e, stackTrace) {
      _logService.log('Error creating Wine prefix "$prefixName": $e\n$stackTrace', LogLevel.error);
      onStatusUpdate('Error creating Wine prefix "$prefixName": $e');
      return null;
    }
  }

  Future<String> _getDownloadDirectory() async {
    // Use absolute path to avoid relative path issues
    return path.join(Directory.current.absolute.path, "wine_builds");
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
        baseDir = path.join(Directory.current.absolute.path, 'wineprefixes');
        _logService.log("Warning: HOME environment variable not set. Using relative path for prefixes: $baseDir", LogLevel.warning);
      }
      if (settings.prefixDirectory.isNotEmpty) {
        // Log if the specified directory didn't exist and we fell back
        _logService.log("Warning: Specified prefix directory '${settings.prefixDirectory}' does not exist or is invalid. Falling back to '$baseDir'.", LogLevel.warning);
      }
    }
    
    // Create the type-specific subfolder
    final typeDir = path.join(baseDir, 'wine');
    Directory(typeDir).createSync(recursive: true);
    
    return path.join(typeDir, prefixName);
  }

  Future<void> _initializeWinePrefix(String prefixPath, String buildPath, Settings settings, StatusCallback onStatusUpdate) async {
    final baseEnv = {
      'WINEPREFIX': prefixPath,
      'PATH': '$buildPath/bin:${Platform.environment['PATH']}',
      'LD_LIBRARY_PATH': '$buildPath/lib64:$buildPath/lib:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
      'GST_PLUGIN_SYSTEM_PATH_1_0': '',
      'WINEDLLOVERRIDES': 'winemenubuilder.exe=d',
    };

    final fullEnv = {...Platform.environment, ...baseEnv};
    final setupShell = Shell(environment: fullEnv, verbose: false);

    _logService.log('Initializing Wine prefix using build from $buildPath');

    String wineExecutablePath = path.join(buildPath, 'bin', 'wine');

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

    // Run wineboot -u for initialization
    onStatusUpdate('Running wineboot...');
    _logService.log('Running wineboot -u...');
    await setupShell.run('"$wineExecutablePath" wineboot -u');

    // Set Windows version to win10
    onStatusUpdate('Setting Windows version to win10...');
    _logService.log('Running winecfg /v win10...');
    await setupShell.run('"$wineExecutablePath" winecfg /v win10');
    _logService.log('Windows version set to win10.');

    // Install core dependencies
    final dependencies = [
      'corefonts',
      'd3dx9', 'd3dcompiler_43', 'd3dcompiler_47', 
      'msls31', 'mono', 'gecko'
    ];

    onStatusUpdate('Installing core dependencies...');
    for (final dep in dependencies) {
      onStatusUpdate('Installing $dep...');
      _logService.log('Installing winetricks $dep...');
      try {
        final result = await _shell.run(
          'WINEPREFIX="$prefixPath" WINE="$wineExecutablePath" winetricks -q $dep',
        );
        _logService.log('$dep installation finished. ${result.outText}');
      } catch (e) {
        _logService.log('Warning: Failed to install $dep: $e', LogLevel.warning);
        onStatusUpdate('Warning: Failed to install $dep: $e');
      }
    }
    
    // Create a temporary WinePrefix object for component installation
    final tempPrefix = WinePrefix(
      name: path.basename(prefixPath), 
      path: prefixPath, 
      wineBuildPath: buildPath, 
      type: PrefixType.wine, 
      exeEntries: []
    );

    // Install DXVK
    onStatusUpdate('Installing DXVK...');
    try {
      await _componentInstaller.installDxvk(tempPrefix, settings, progressCallback: onStatusUpdate);
      _logService.log('DXVK installation completed.');
    } catch (e) {
      _logService.log('Warning: Failed to install DXVK: $e', LogLevel.warning);
      onStatusUpdate('Warning: Failed to install DXVK: $e');
    }
    
    // Install VKD3D-Proton
    onStatusUpdate('Installing VKD3D-Proton...');
    try {
      await _componentInstaller.installVkd3d(tempPrefix, settings, progressCallback: onStatusUpdate);
      _logService.log('VKD3D-Proton installation completed.');
    } catch (e) {
      _logService.log('Warning: Failed to install VKD3D-Proton: $e', LogLevel.warning);
      onStatusUpdate('Warning: Failed to install VKD3D-Proton: $e');
    }
    
    // Run winetricks verbs to ensure proper configuration
    final winetricksVerbs = ['dxvk', 'vkd3d', 'dxvk_nvapi'];
    for (final verb in winetricksVerbs) {
      onStatusUpdate('Configuring $verb via winetricks...');
      _logService.log('Running winetricks $verb...');
      try {
        await _componentInstaller.installComponent(
          prefixPath: prefixPath,
          component: verb,
          wineExecutablePath: wineExecutablePath,
          onStatusUpdate: (status) {
            onStatusUpdate('Configuring $verb: $status');
            _logService.log('Winetricks ($verb): $status');
          },
        );
        _logService.log('Winetricks configuration for $verb completed.');
      } catch (e) {
        _logService.log('Warning: Failed to configure $verb via winetricks: $e', LogLevel.warning);
        onStatusUpdate('Warning: Failed to configure $verb: $e');
      }
    }

    _logService.log('Wine prefix initialization completed with DXVK and VKD3D-Proton installed.');
  }
} 