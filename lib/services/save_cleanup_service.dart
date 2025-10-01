import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/prefix_models.dart';
import '../services/log_service.dart';

class SaveCleanupService {
  final LogService _logService;

  SaveCleanupService(this._logService);

  /// Cleans up save data from non-user directories before launching a game
  /// This ensures save data is only stored in the user directory as specified by -savetouserdir
  Future<void> cleanupNonUserSaveData(GameEntry game) async {
    try {
      _logService.log('Starting save data cleanup for ${game.exe.name} in prefix ${game.prefix.name}...');
      
      final prefix = game.prefix;
      final gameName = game.exe.name;
      
      // Only clean up save data for this specific game in this specific prefix
      final nonUserSavePaths = _getNonUserSavePaths(prefix, gameName);
      
      int cleanedCount = 0;
      int totalSize = 0;
      
      for (final savePath in nonUserSavePaths) {
        final directory = Directory(savePath);
        if (await directory.exists()) {
          // Double-check that this is actually save data for this specific game
          if (await _isGameSaveData(directory, gameName)) {
            final files = await directory.list(recursive: true, followLinks: false).toList();
            
            // Calculate total size before deletion
            int dirSize = 0;
            for (final file in files) {
              if (file is File) {
                try {
                  dirSize += await file.stat().then((s) => s.size);
                } catch (e) {
                  // Ignore files that can't be accessed
                }
              }
            }
            
            // Delete the directory and all its contents
            await directory.delete(recursive: true);
            
            cleanedCount += files.length;
            totalSize += dirSize;
            
            _logService.log('Cleaned save data from: $savePath (${files.length} files, ${_formatFileSize(dirSize)})');
          } else {
            _logService.log('Skipping $savePath - not save data for ${game.exe.name}');
          }
        }
      }
      
      if (cleanedCount > 0) {
        _logService.log('Save cleanup completed for ${game.exe.name}: $cleanedCount files removed, ${_formatFileSize(totalSize)} freed');
      } else {
        _logService.log('No non-user save data found to clean up for ${game.exe.name}');
      }
      
    } catch (e) {
      _logService.log('Error during save data cleanup for ${game.exe.name}: $e', LogLevel.error);
      // Don't throw - cleanup failure shouldn't prevent game launch
    }
  }

  /// Gets a list of non-user save data paths that should be cleaned up
  List<String> _getNonUserSavePaths(WinePrefix prefix, String gameName) {
    final prefixPath = prefix.path;
    final gameNameLower = gameName.toLowerCase().replaceAll(' ', '');
    
    return [
      // Common Windows save locations (non-user)
      p.join(prefixPath, 'drive_c', 'ProgramData', gameName),
      p.join(prefixPath, 'drive_c', 'ProgramData', gameNameLower),
      p.join(prefixPath, 'drive_c', 'Program Files', gameName),
      p.join(prefixPath, 'drive_c', 'Program Files', gameNameLower),
      p.join(prefixPath, 'drive_c', 'Program Files (x86)', gameName),
      p.join(prefixPath, 'drive_c', 'Program Files (x86)', gameNameLower),
      
      // Steam-specific non-user locations
      p.join(prefixPath, 'drive_c', 'Program Files', 'Steam', 'steamapps', 'common', gameName),
      p.join(prefixPath, 'drive_c', 'Program Files', 'Steam', 'steamapps', 'common', gameNameLower),
      p.join(prefixPath, 'drive_c', 'Program Files (x86)', 'Steam', 'steamapps', 'common', gameName),
      p.join(prefixPath, 'drive_c', 'Program Files (x86)', 'Steam', 'steamapps', 'common', gameNameLower),
      
      // Game-specific common non-user paths
      p.join(prefixPath, 'drive_c', 'ProgramData', 'Microsoft', 'Windows', 'Start Menu', 'Programs', gameName),
      p.join(prefixPath, 'drive_c', 'ProgramData', 'Microsoft', 'Windows', 'Start Menu', 'Programs', gameNameLower),
      
      // Additional common save locations that might not be in user directory
      p.join(prefixPath, 'drive_c', 'users', 'Public', 'Documents', gameName),
      p.join(prefixPath, 'drive_c', 'users', 'Public', 'Documents', gameNameLower),
      p.join(prefixPath, 'drive_c', 'users', 'Public', 'Saved Games', gameName),
      p.join(prefixPath, 'drive_c', 'users', 'Public', 'Saved Games', gameNameLower),
    ];
  }

  /// Verifies that a directory actually contains save data for the specific game
  Future<bool> _isGameSaveData(Directory directory, String gameName) async {
    try {
      final gameNameLower = gameName.toLowerCase().replaceAll(' ', '');
      final dirName = directory.path.split('/').last.toLowerCase().replaceAll(' ', '');
      
      // Check if the directory name matches the game name (exact or partial)
      if (dirName.contains(gameNameLower) || gameNameLower.contains(dirName)) {
        return true;
      }
      
      // Check if the directory contains common save file extensions
      final files = await directory.list(recursive: true, followLinks: false).toList();
      int saveFileCount = 0;
      
      for (final file in files) {
        if (file is File) {
          final fileName = file.path.toLowerCase();
          if (fileName.endsWith('.sav') || 
              fileName.endsWith('.save') || 
              fileName.endsWith('.dat') || 
              fileName.endsWith('.cfg') || 
              fileName.endsWith('.ini') ||
              fileName.endsWith('.json') ||
              fileName.endsWith('.xml')) {
            saveFileCount++;
          }
        }
      }
      
      // If we found save files, consider it save data
      return saveFileCount > 0;
      
    } catch (e) {
      _logService.log('Error checking if directory is save data: $e', LogLevel.error);
      return false;
    }
  }

  /// Formats file size in human-readable format
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
