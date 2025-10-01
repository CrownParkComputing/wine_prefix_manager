import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import '../models/prefix_models.dart';
import 'log_service.dart';

class CompressedGameService {
  final LogService _logService = LogService();
  final Map<String, CompressedGameSession> _activeSessions = {};

  /// Extracts a compressed game before launching
  Future<String> extractGameForLaunch(ExeEntry compressedGame) async {
    if (!compressedGame.isCompressed || compressedGame.compressedArchivePath == null) {
      throw Exception('Game is not a compressed game');
    }

    final archivePath = compressedGame.compressedArchivePath!;
    final extractPath = compressedGame.extractedBasePath!;
    
    _logService.log('Extracting compressed game: ${compressedGame.name}');
    
    // Create extract directory if it doesn't exist
    final extractDir = Directory(extractPath);
    if (!await extractDir.exists()) {
      await extractDir.create(recursive: true);
    }

    // Check if already extracted and up-to-date
    final extractedGamePath = await _findGameExecutable(extractPath);
    if (extractedGamePath != null && await File(extractedGamePath).exists()) {
      final archiveModified = await File(archivePath).lastModified();
      final extractedModified = await File(extractedGamePath).lastModified();
      
      if (extractedModified.isAfter(archiveModified)) {
        _logService.log('Game already extracted and up-to-date');
        return extractedGamePath;
      }
    }

    // Create extraction script
    final tempDir = Directory.systemTemp.createTempSync('game_extract_');
    final scriptPath = p.join(tempDir.path, 'extract_script.sh');
    
    String extractCommand;
    final fileName = p.basename(archivePath).toLowerCase();
    
    if (fileName.endsWith('.tar.zst')) {
      extractCommand = 'zstd -d "$archivePath" -c | tar xf - -C "$extractPath"';
    } else if (fileName.endsWith('.tar.gz') || fileName.endsWith('.tgz')) {
      extractCommand = 'tar xzf "$archivePath" -C "$extractPath"';
    } else if (fileName.endsWith('.tar.xz')) {
      extractCommand = 'tar xJf "$archivePath" -C "$extractPath"';
    } else if (fileName.endsWith('.zip')) {
      extractCommand = 'unzip -q -o "$archivePath" -d "$extractPath"';
    } else if (fileName.endsWith('.7z')) {
      extractCommand = '7z x "$archivePath" -o"$extractPath" -y';
    } else {
      throw Exception('Unsupported archive format: $fileName');
    }

    final scriptContent = '''#!/bin/bash
set -e
echo "Extracting ${compressedGame.name}..."
$extractCommand
echo "Extraction complete!"
''';

    await File(scriptPath).writeAsString(scriptContent);
    await Process.run('chmod', ['+x', scriptPath]);

    // Run extraction
    final result = await Process.run('bash', [scriptPath]);
    
    // Cleanup temp script
    await tempDir.delete(recursive: true);

    if (result.exitCode != 0) {
      throw Exception('Extraction failed: ${result.stderr}');
    }

    // Find the game executable
    final gameExePath = await _findGameExecutable(extractPath);
    if (gameExePath == null) {
      throw Exception('Could not find game executable after extraction');
    }

    // Create session to monitor file changes
    final session = CompressedGameSession(
      originalGame: compressedGame,
      extractedPath: extractPath,
      gameExecutable: gameExePath,
      startTime: DateTime.now(),
    );
    
    _activeSessions[compressedGame.path] = session;
    
    _logService.log('Game extracted successfully: $gameExePath');
    return gameExePath;
  }

  /// Monitors for file changes and offers recompression after game ends
  Future<void> handleGameExit(ExeEntry compressedGame, WinePrefix prefix) async {
    final session = _activeSessions[compressedGame.path];
    if (session == null) return;

    _logService.log('Checking for file changes in ${compressedGame.name}');

    // Check if files have been modified since extraction
    final hasChanges = await _detectFileChanges(session);
    
    if (hasChanges) {
      _logService.log('File changes detected, offering recompression');
      // This would trigger UI notification for recompression
      // For now, just set the flag
      await _markGameNeedsRecompression(compressedGame, prefix);
    }

    // Remove session
    _activeSessions.remove(compressedGame.path);
  }

  /// Creates a new compressed archive with updated files
  Future<void> recompressGame(ExeEntry compressedGame, List<String> additionalPaths) async {
    if (!compressedGame.isCompressed || compressedGame.compressedArchivePath == null) {
      throw Exception('Game is not a compressed game');
    }

    final archivePath = compressedGame.compressedArchivePath!;
    final extractPath = compressedGame.extractedBasePath!;
    
    _logService.log('Recompressing game: ${compressedGame.name}');

    // Create backup of original archive
    final backupPath = '$archivePath.backup.${DateTime.now().millisecondsSinceEpoch}';
    await File(archivePath).copy(backupPath);

    try {
      // Create new archive with updated files
      final tempDir = Directory.systemTemp.createTempSync('recompress_');
      final scriptPath = p.join(tempDir.path, 'recompress_script.sh');
      
      String compressCommand;
      final fileName = p.basename(archivePath).toLowerCase();
      
      if (fileName.endsWith('.tar.zst')) {
        compressCommand = '''
          cd "${p.dirname(extractPath)}"
          tar cf - "${p.basename(extractPath)}" ${additionalPaths.map((path) => '"${p.basename(path)}"').join(' ')} | zstd -3 -o "$archivePath"
        ''';
      } else if (fileName.endsWith('.tar.gz')) {
        compressCommand = '''
          cd "${p.dirname(extractPath)}"
          tar czf "$archivePath" "${p.basename(extractPath)}" ${additionalPaths.map((path) => '"${p.basename(path)}"').join(' ')}
        ''';
      } else {
        throw Exception('Recompression not supported for this format yet');
      }

      final scriptContent = '''#!/bin/bash
set -e
echo "Recompressing ${compressedGame.name}..."
$compressCommand
echo "Recompression complete!"
''';

      await File(scriptPath).writeAsString(scriptContent);
      await Process.run('chmod', ['+x', scriptPath]);

      // Run recompression
      final result = await Process.run('bash', [scriptPath]);
      
      // Cleanup temp script
      await tempDir.delete(recursive: true);

      if (result.exitCode != 0) {
        throw Exception('Recompression failed: ${result.stderr}');
      }

      // Remove backup on success
      await File(backupPath).delete();
      
      _logService.log('Game recompressed successfully');
      
    } catch (e) {
      // Restore backup on failure
      await File(backupPath).copy(archivePath);
      await File(backupPath).delete();
      rethrow;
    }
  }

  /// Finds the game executable in the extracted directory
  Future<String?> _findGameExecutable(String extractPath) async {
    final dir = Directory(extractPath);
    if (!await dir.exists()) return null;

    // Look for exe files
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
        final name = p.basename(entity.path).toLowerCase();
        // Skip common system/installer files
        if (!name.contains('unins') && 
            !name.contains('setup') && 
            !name.contains('install') &&
            !name.contains('redist') &&
            !name.contains('vcredist') &&
            !name.contains('directx')) {
          return entity.path;
        }
      }
    }
    return null;
  }

  /// Detects if files have been modified since extraction
  Future<bool> _detectFileChanges(CompressedGameSession session) async {
    try {
      final dir = Directory(session.extractedPath);
      if (!await dir.exists()) return false;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final lastModified = await entity.lastModified();
          if (lastModified.isAfter(session.startTime)) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      _logService.log('Error detecting file changes: $e', LogLevel.warning);
      return false;
    }
  }

  /// Marks a game as needing recompression
  Future<void> _markGameNeedsRecompression(ExeEntry compressedGame, WinePrefix prefix) async {
    // This would update the game entry in the prefix
    // Implementation depends on how we want to handle this in the UI
    _logService.log('Game ${compressedGame.name} marked as needing recompression');
  }

  /// Cleans up extracted files for a compressed game
  Future<void> cleanupExtractedGame(ExeEntry compressedGame) async {
    if (!compressedGame.isCompressed || compressedGame.extractedBasePath == null) {
      return;
    }

    final extractPath = compressedGame.extractedBasePath!;
    final extractDir = Directory(extractPath);
    
    if (await extractDir.exists()) {
      await extractDir.delete(recursive: true);
      _logService.log('Cleaned up extracted files for ${compressedGame.name}');
    }
  }
}

class CompressedGameSession {
  final ExeEntry originalGame;
  final String extractedPath;
  final String gameExecutable;
  final DateTime startTime;

  CompressedGameSession({
    required this.originalGame,
    required this.extractedPath,
    required this.gameExecutable,
    required this.startTime,
  });
} 