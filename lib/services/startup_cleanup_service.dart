import 'dart:io';
import 'package:path/path.dart' as p;
import 'log_service.dart';

class StartupCleanupService {
  final LogService _logService;

  StartupCleanupService(this._logService);

  /// Performs startup cleanup of old prefix cache and config data
  Future<void> performStartupCleanup() async {
    try {
      _logService.log('Starting startup cleanup...');
      
      int totalCleaned = 0;
      int totalSize = 0;
      
    // Clean up Wine prefix cache
    final wineCacheCleaned = await _cleanupWineCache();
    totalCleaned += wineCacheCleaned['files'] ?? 0;
    totalSize += wineCacheCleaned['size'] ?? 0;
      
    // Clean up old config files
    final configCleaned = await _cleanupOldConfigFiles();
    totalCleaned += configCleaned['files'] ?? 0;
    totalSize += configCleaned['size'] ?? 0;
      
    // Clean up temporary files
    final tempCleaned = await _cleanupTemporaryFiles();
    totalCleaned += tempCleaned['files'] ?? 0;
    totalSize += tempCleaned['size'] ?? 0;
      
    // Clean up old log files
    final logCleaned = await _cleanupOldLogFiles();
    totalCleaned += logCleaned['files'] ?? 0;
    totalSize += logCleaned['size'] ?? 0;
      
      if (totalCleaned > 0) {
        _logService.log('Startup cleanup completed: $totalCleaned files removed, ${_formatFileSize(totalSize)} freed');
      } else {
        _logService.log('No old files found to clean up');
      }
      
    } catch (e) {
      _logService.log('Error during startup cleanup: $e', LogLevel.error);
    }
  }

  /// Cleans up Wine prefix cache files
  Future<Map<String, int>> _cleanupWineCache() async {
    int filesCleaned = 0;
    int totalSize = 0;
    
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      if (homeDir.isEmpty) return {'files': 0, 'size': 0};
      
      // Common Wine cache locations
      final cachePaths = [
        p.join(homeDir, '.cache', 'wine'),
        p.join(homeDir, '.local', 'share', 'wine'),
        p.join(homeDir, '.wine'),
        p.join(homeDir, '.steam', 'steam', 'steamapps', 'compatdata'),
        p.join(homeDir, '.steam', 'steam', 'steamapps', 'shadercache'),
        p.join(homeDir, '.steam', 'steam', 'steamapps', 'temp'),
      ];
      
      for (final cachePath in cachePaths) {
        final directory = Directory(cachePath);
        if (await directory.exists()) {
          final result = await _cleanupDirectory(directory, 'Wine cache');
          filesCleaned += result['files'] ?? 0;
          totalSize += result['size'] ?? 0;
        }
      }
      
    } catch (e) {
      _logService.log('Error cleaning Wine cache: $e', LogLevel.error);
    }
    
    return {'files': filesCleaned, 'size': totalSize};
  }

  /// Cleans up old config files
  Future<Map<String, int>> _cleanupOldConfigFiles() async {
    int filesCleaned = 0;
    int totalSize = 0;
    
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      if (homeDir.isEmpty) return {'files': 0, 'size': 0};
      
      // Common config locations
      final configPaths = [
        p.join(homeDir, '.config', 'wine'),
        p.join(homeDir, '.config', 'steam'),
        p.join(homeDir, '.local', 'share', 'applications'),
        p.join(homeDir, '.local', 'share', 'mime'),
        p.join(homeDir, '.local', 'share', 'desktop-directories'),
      ];
      
      for (final configPath in configPaths) {
        final directory = Directory(configPath);
        if (await directory.exists()) {
          final result = await _cleanupDirectory(directory, 'Config files');
          filesCleaned += result['files'] ?? 0;
          totalSize += result['size'] ?? 0;
        }
      }
      
    } catch (e) {
      _logService.log('Error cleaning config files: $e', LogLevel.error);
    }
    
    return {'files': filesCleaned, 'size': totalSize};
  }

  /// Cleans up temporary files
  Future<Map<String, int>> _cleanupTemporaryFiles() async {
    int filesCleaned = 0;
    int totalSize = 0;
    
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      if (homeDir.isEmpty) return {'files': 0, 'size': 0};
      
      // Common temp locations
      final tempPaths = [
        p.join(homeDir, '.cache', 'temp'),
        p.join(homeDir, '.local', 'share', 'Trash'),
        p.join(homeDir, '.local', 'share', 'recently-used.xbel'),
        p.join(homeDir, '.thumbnails'),
        p.join(homeDir, '.cache', 'thumbnails'),
      ];
      
      for (final tempPath in tempPaths) {
        final directory = Directory(tempPath);
        if (await directory.exists()) {
          final result = await _cleanupDirectory(directory, 'Temporary files');
          filesCleaned += result['files'] ?? 0;
          totalSize += result['size'] ?? 0;
        }
      }
      
    } catch (e) {
      _logService.log('Error cleaning temporary files: $e', LogLevel.error);
    }
    
    return {'files': filesCleaned, 'size': totalSize};
  }

  /// Cleans up old log files
  Future<Map<String, int>> _cleanupOldLogFiles() async {
    int filesCleaned = 0;
    int totalSize = 0;
    
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      if (homeDir.isEmpty) return {'files': 0, 'size': 0};
      
      // Common log locations
      final logPaths = [
        p.join(homeDir, '.cache', 'logs'),
        p.join(homeDir, '.local', 'share', 'logs'),
        p.join(homeDir, '.wine', 'logs'),
        p.join(homeDir, '.steam', 'steam', 'logs'),
      ];
      
      for (final logPath in logPaths) {
        final directory = Directory(logPath);
        if (await directory.exists()) {
          final result = await _cleanupDirectory(directory, 'Log files');
          filesCleaned += result['files'] ?? 0;
          totalSize += result['size'] ?? 0;
        }
      }
      
    } catch (e) {
      _logService.log('Error cleaning log files: $e', LogLevel.error);
    }
    
    return {'files': filesCleaned, 'size': totalSize};
  }

  /// Cleans up a directory and returns file count and size
  Future<Map<String, int>> _cleanupDirectory(Directory directory, String description) async {
    int filesCleaned = 0;
    int totalSize = 0;
    
    try {
      final files = await directory.list(recursive: true, followLinks: false).toList();
      
      for (final file in files) {
        if (file is File) {
          try {
            final stat = await file.stat();
            final age = DateTime.now().difference(stat.modified);
            
            // Only clean files older than 7 days
            if (age.inDays > 7) {
              totalSize += stat.size;
              await file.delete();
              filesCleaned++;
            }
          } catch (e) {
            // Ignore files that can't be accessed
          }
        }
      }
      
      if (filesCleaned > 0) {
        _logService.log('Cleaned $description: $filesCleaned files, ${_formatFileSize(totalSize)}');
      }
      
    } catch (e) {
      _logService.log('Error cleaning directory $description: $e', LogLevel.error);
    }
    
    return {'files': filesCleaned, 'size': totalSize};
  }

  /// Formats file size in human-readable format
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

