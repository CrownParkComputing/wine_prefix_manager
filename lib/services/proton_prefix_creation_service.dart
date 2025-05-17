import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as path;
import '../models/settings.dart';
import '../models/wine_build.dart';
import '../models/prefix_models.dart';
import 'log_service.dart';

typedef StatusCallback = void Function(String status);
typedef ProgressCallback = void Function(double progress);

/// Service for creating Proton prefixes.
/// Note: Only the two latest Proton versions are made available for selection
/// to limit choices and ensure better compatibility.
class ProtonPrefixCreationService {
  final Dio _dio = Dio();
  final Shell _shell = Shell(verbose: false);
  final LogService _logService = LogService();

  // Add a field to track the selected build for directory organization
  BaseBuild? _lastSelectedBuild;

  Future<WinePrefix?> createProtonPrefix({
    required BaseBuild? selectedBuild,
    required String prefixName,
    required Settings settings,
    required StatusCallback onStatusUpdate,
    required ProgressCallback onProgressUpdate,
  }) async {
    // Store the selected build for use in _getPrefixPath
    _lastSelectedBuild = selectedBuild;
    
    onStatusUpdate('Starting Proton prefix creation for "$prefixName"...');
    _logService.log('Starting Proton prefix creation for "$prefixName"...');

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
      
      // Create a sanitized name for the extraction directory (replace spaces with underscores)
      String sanitizedName = fileName.replaceAll(' ', '_');
      
      // Handle both .tar.gz and .tar.xz extensions
      String extractedName = sanitizedName
          .replaceAll('.tar.gz', '')
          .replaceAll('.tar.xz', '');
          
      extractedDir = path.join(downloadDir, extractedName);
      _logService.log('Target extraction directory: $extractedDir');

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
        final result = await _shell.run(tarCommand);
        String extractionOutput = result.outText;
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
          String altExtractedDir = path.join(downloadDir, 'wine-proton-' + extractedName.split('-').last);
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
        'type': PrefixType.proton.toString()
      }));
      _logService.log('Prefix config saved.');

      // 5. Initialize Prefix
      onStatusUpdate('Initializing prefix (this might take a moment)...');
      await _initializeProtonPrefix(prefixPath, extractedDir, onStatusUpdate);
      _logService.log('Proton prefix initialized.');

      onStatusUpdate('Proton prefix "$prefixName" created successfully!');
      _logService.log('Proton prefix "$prefixName" created successfully!');

      // 6. Return new WinePrefix object
      return WinePrefix(
        name: prefixName,
        path: prefixPath,
        wineBuildPath: extractedDir,
        type: PrefixType.proton,
        exeEntries: [],
      );

    } catch (e, stackTrace) {
      _logService.log('Error creating Proton prefix "$prefixName": $e\n$stackTrace', LogLevel.error);
      onStatusUpdate('Error creating Proton prefix "$prefixName": $e');
      return null;
    }
  }

  Future<String> _getDownloadDirectory() async {
    // Use absolute path to avoid relative path issues
    return path.join(Directory.current.absolute.path, "proton_builds");
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
    
    // Create the type-specific subfolder based on the specific Proton build source
    String typeDir;
    if (_lastSelectedBuild != null) {
      if (_lastSelectedBuild!.name.contains('GE-Proton')) {
        typeDir = path.join(baseDir, 'proton-ge');
      } else if (_lastSelectedBuild!.name.contains('Kronek') || _lastSelectedBuild!.name.contains('wine-proton')) {
        typeDir = path.join(baseDir, 'proton-kronek');
      } else {
        // For other Proton builds or when source can't be determined
        typeDir = path.join(baseDir, 'proton');
      }
    } else {
      // Fallback if build not known
      typeDir = path.join(baseDir, 'proton');
    }
    
    Directory(typeDir).createSync(recursive: true);
    return path.join(typeDir, prefixName);
  }

  Future<void> _initializeProtonPrefix(String prefixPath, String buildPath, StatusCallback onStatusUpdate) async {
    _logService.log('Initializing Proton prefix using build from $buildPath');
    
    // Check if proton executable exists
    String protonExecutablePath = path.join(buildPath, 'proton');
    if (await File(protonExecutablePath).exists()) {
      _logService.log('Found Proton executable at $protonExecutablePath');
      // Make it executable
      try {
        await Shell(verbose: false).run('chmod +x "$protonExecutablePath"');
      } catch (e) {
        _logService.log('Warning: Could not set executable permission for proton: $e', LogLevel.warning);
      }
    } else {
      _logService.log('Proton executable not found at $protonExecutablePath', LogLevel.warning);
    }
    
    // Proton-GE uses a different structure, check various possible locations for wine
    List<String> possibleWinePaths = [
      path.join(buildPath, 'bin', 'wine'),              // Standard location
      path.join(buildPath, 'files', 'bin', 'wine'),     // Proton-GE structure
      path.join(buildPath, 'dist', 'bin', 'wine'),      // Alternative Proton structure
    ];
    
    String? wineExecutablePath;
    for (var winePath in possibleWinePaths) {
      _logService.log('Checking for wine at: $winePath');
      if (await File(winePath).exists()) {
        wineExecutablePath = winePath;
        _logService.log('Found wine executable at $winePath');
        break;
      }
    }
    
    if (wineExecutablePath == null) {
      final errorMsg = 'Could not find wine executable in Proton build at $buildPath';
      _logService.log(errorMsg, LogLevel.error);
      throw Exception(errorMsg);
    }
    
    // Ensure wine is executable
    try {
      await Shell(verbose: false).run('chmod +x "$wineExecutablePath"');
    } catch (e) {
      _logService.log('Warning: Could not set executable permission for wine: $e', LogLevel.warning);
    }
    
    // Get the directory containing wine
    final wineBinDir = path.dirname(wineExecutablePath);
    final protonLibDir = path.join(buildPath, 'files', 'lib');
    final protonLib64Dir = path.join(buildPath, 'files', 'lib64');
    
    // Set environment variables with proper Proton paths
    final baseEnv = {
      'WINEPREFIX': prefixPath,
      'PATH': '$wineBinDir:${Platform.environment['PATH']}',
      'LD_LIBRARY_PATH': '$protonLib64Dir:$protonLibDir:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
      'GST_PLUGIN_SYSTEM_PATH_1_0': '',
      'WINEDLLOVERRIDES': 'winemenubuilder.exe=d',
      'STEAM_COMPAT_CLIENT_INSTALL_PATH': Platform.environment['HOME'] ?? '.',
      'STEAM_COMPAT_DATA_PATH': prefixPath,
      'UMU_ID': '1',
    };

    final fullEnv = {...Platform.environment, ...baseEnv};
    final setupShell = Shell(environment: fullEnv, verbose: false);

    // Run wineboot -u for initialization
    onStatusUpdate('Running wineboot...');
    _logService.log('Running wineboot -u...');
    await setupShell.run('"$wineExecutablePath" wineboot -u');

    _logService.log('Proton prefix initialization command finished.');
  }
} 