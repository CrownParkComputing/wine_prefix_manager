import 'dart:convert';
import 'dart:io';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as path;
import '../models/settings.dart';
import '../models/prefix_models.dart';
import 'wine_component_installer.dart';
import 'log_service.dart';

typedef StatusCallback = void Function(String status);
typedef ProgressCallback = void Function(double progress);

class CustomPrefixCreationService {
  final Shell _shell = Shell(verbose: false);
  final WineComponentInstaller _componentInstaller = WineComponentInstaller();
  final LogService _logService = LogService();

  Future<WinePrefix?> createCustomPrefix({
    required String prefixName,
    required Settings settings,
    required StatusCallback onStatusUpdate,
    required ProgressCallback onProgressUpdate,
  }) async {
    onStatusUpdate('Starting custom prefix creation for "$prefixName"...');
    _logService.log('Starting custom prefix creation for "$prefixName"...');

    try {
      onStatusUpdate('Creating Custom prefix directory...');
      String prefixPath = _getPrefixPath(settings, prefixName);
      await Directory(prefixPath).create(recursive: true);
      _logService.log('Custom prefix directory created at: $prefixPath');

      // Save config indicating system wine is used
      final configFile = File(path.join(prefixPath, '.prefix_config'));
      await configFile.writeAsString(jsonEncode({
        'buildPath': 'system', // Indicate system wine
        'type': PrefixType.wine.toString()
      }));
      _logService.log('Custom prefix config saved.');

      // Initialize and configure the custom prefix using system wine
      await _initializeCustomPrefix(prefixPath, settings, onStatusUpdate);

      onStatusUpdate('Custom prefix "$prefixName" created successfully!');
      _logService.log('Custom prefix "$prefixName" created successfully!');

      return WinePrefix(
        name: prefixName,
        path: prefixPath,
        wineBuildPath: 'system', // Indicate system wine was used
        type: PrefixType.wine,
        exeEntries: [],
      );
    } catch (e, stackTrace) {
      _logService.log('Error creating Custom prefix "$prefixName": $e\n$stackTrace', LogLevel.error);
      onStatusUpdate('Error creating Custom prefix "$prefixName": $e');
      return null;
    }
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
    }      // Create the type-specific subfolder
    final typeDir = path.join(baseDir, 'wine');
    Directory(typeDir).createSync(recursive: true);
    
    return path.join(typeDir, prefixName);
  }

  /// Initializes a Custom prefix using system wine and installs components.
  Future<void> _initializeCustomPrefix(String prefixPath, Settings settings, StatusCallback onStatusUpdate) async {
    _logService.log('Initializing Custom prefix at $prefixPath using system wine...');
    const wineExecutable = 'wine'; // Assume system wine is in PATH
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

      onStatusUpdate('Installing core dependencies...');
      for (final dep in dependencies) {
        onStatusUpdate('Installing $dep...');
        _logService.log('Installing winetricks $dep...');
        final result = await _shell.run(
          'WINEPREFIX="$prefixPath" winetricks -q $dep',
        );
        _logService.log('$dep installation finished. ${result.outText}');
      }
      onStatusUpdate('Core dependencies installed.');
      _logService.log('All winetricks dependencies installed.');
      
      // 4. Install DXVK
      onStatusUpdate('Installing DXVK...');
      try {
        final tempPrefix = WinePrefix(name: path.basename(prefixPath), path: prefixPath, wineBuildPath: 'system', type: PrefixType.wine, exeEntries: []);
        await _componentInstaller.installDxvk(tempPrefix, settings, progressCallback: onStatusUpdate);
        _logService.log('DXVK installation attempted.');
      } catch (e) {
        _logService.log('Failed to install DXVK: $e', LogLevel.error);
        onStatusUpdate('Error installing DXVK: $e');
      }
      
      // 5. Install VKD3D-Proton
      onStatusUpdate('Installing VKD3D-Proton...');
      try {
        final tempPrefix = WinePrefix(name: path.basename(prefixPath), path: prefixPath, wineBuildPath: 'system', type: PrefixType.wine, exeEntries: []);
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
      _logService.log('Error during Custom prefix initialization: $e\n$stackTrace', LogLevel.error);
      onStatusUpdate('Error initializing Custom prefix: $e');
      rethrow; // Re-throw to be caught by the main function
    }
  }
} 