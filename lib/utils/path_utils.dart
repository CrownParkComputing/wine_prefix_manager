import 'dart:io';
import 'package:path/path.dart' as path;
import 'logger.dart';

// appNameForPaths is not strictly needed here if we use a fixed folder name like wpm_settings
// const String appNameForPaths = 'wine_prefix_manager'; 
const String targetAppDataFolderName = 'wpm_settings';

Future<String> getBaseAppDataPath() async {
  final homeDir = Platform.environment['HOME'];
  if (homeDir == null || homeDir.isEmpty) {
    logWarning('Warning: HOME environment variable not set. Using temporary directory for app data.');
    // Fallback to a temporary directory, less ideal for persistent data.
    final tempDir = await Directory.systemTemp.createTemp(targetAppDataFolderName); 
    return tempDir.path;
  }
  // New preferred path: ~/wpm_settings/
  return path.join(homeDir, targetAppDataFolderName);
} 