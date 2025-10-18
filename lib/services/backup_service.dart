import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;

class BackupResult {
  final bool success;
  final String? backupPath;
  final String? error;

  BackupResult({required this.success, this.backupPath, this.error});
}

class BackupService {
  static const String _backupExtension = '.tar.zst';
  
  /// Creates a backup of files/folders using zstd compression
  /// [sourcePaths] - List of file/folder paths to backup
  /// [backupDir] - Directory where backup will be stored
  /// [backupName] - Name for the backup (without extension)
  /// [onProgress] - Optional callback for progress updates (0.0 to 1.0)
  /// [onStatus] - Optional callback for status messages
  static Future<BackupResult> createBackup({
    required List<String> sourcePaths,
    required String backupDir,
    required String backupName,
    Function(double)? onProgress,
    Function(String)? onStatus,
  }) async {
    try {
      // Ensure backup directory exists
      final backupDirectory = Directory(backupDir);
      if (!backupDirectory.existsSync()) {
        backupDirectory.createSync(recursive: true);
      }

      // Generate unique backup filename with timestamp
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final backupFileName = '${backupName}_$timestamp$_backupExtension';
      final backupPath = p.join(backupDir, backupFileName);

      onStatus?.call('Preparing backup...');
      onProgress?.call(0.1);

      // Check if zstd is available
      final zstdCheck = await Process.run('which', ['zstd']);
      if (zstdCheck.exitCode != 0) {
        return BackupResult(
          success: false,
          error: 'zstd compression tool not found. Please install zstd package.',
        );
      }

      onStatus?.call('Creating archive...');
      onProgress?.call(0.2);

      // Create tar archive with zstd compression
      final tarArgs = <String>[
        '-cf', '-', // Create archive to stdout
        '--exclude=*.tmp',
        '--exclude=*.log',
        '--exclude=*~',
        ...sourcePaths.map((path) => p.basename(path)),
      ];

      // Get the parent directory for tar command
      final workingDir = _getCommonParentDirectory(sourcePaths);

      onStatus?.call('Compressing with zstd...');
      onProgress?.call(0.4);

      // Use pipe: tar | zstd
      final tarProcess = await Process.start(
        'tar',
        tarArgs,
        workingDirectory: workingDir,
      );

      final zstdProcess = await Process.start(
        'zstd',
        ['-19', '-T0', '--long', '-o', backupPath], // High compression, multi-threaded
      );

      // Pipe tar output to zstd input
      tarProcess.stdout.pipe(zstdProcess.stdin);

      onStatus?.call('Finalizing backup...');
      onProgress?.call(0.8);

      // Wait for both processes to complete
      final tarExit = await tarProcess.exitCode;
      final zstdExit = await zstdProcess.exitCode;

      if (tarExit != 0) {
        final tarError = await tarProcess.stderr.transform(const SystemEncoding().decoder).join();
        return BackupResult(
          success: false,
          error: 'tar failed: $tarError',
        );
      }

      if (zstdExit != 0) {
        final zstdError = await zstdProcess.stderr.transform(const SystemEncoding().decoder).join();
        return BackupResult(
          success: false,
          error: 'zstd compression failed: $zstdError',
        );
      }

      onProgress?.call(1.0);
      onStatus?.call('Backup completed successfully!');

      // Verify backup file was created
      final backupFile = File(backupPath);
      if (!backupFile.existsSync()) {
        return BackupResult(
          success: false,
          error: 'Backup file was not created',
        );
      }

      return BackupResult(
        success: true,
        backupPath: backupPath,
      );
    } catch (e) {
      return BackupResult(
        success: false,
        error: 'Backup failed: $e',
      );
    }
  }

  /// Restores a backup file
  /// [backupPath] - Path to the backup file (.tar.zst)
  /// [restoreDir] - Directory where files will be extracted
  /// [onProgress] - Optional callback for progress updates (0.0 to 1.0)
  /// [onStatus] - Optional callback for status messages
  static Future<BackupResult> restoreBackup({
    required String backupPath,
    required String restoreDir,
    Function(double)? onProgress,
    Function(String)? onStatus,
  }) async {
    try {
      final backupFile = File(backupPath);
      if (!backupFile.existsSync()) {
        return BackupResult(
          success: false,
          error: 'Backup file not found: $backupPath',
        );
      }

      // Ensure restore directory exists
      final restoreDirectory = Directory(restoreDir);
      if (!restoreDirectory.existsSync()) {
        restoreDirectory.createSync(recursive: true);
      }

      onStatus?.call('Preparing restore...');
      onProgress?.call(0.1);

      // Check if zstd is available
      final zstdCheck = await Process.run('which', ['zstd']);
      if (zstdCheck.exitCode != 0) {
        return BackupResult(
          success: false,
          error: 'zstd compression tool not found. Please install zstd package.',
        );
      }

      onStatus?.call('Decompressing backup...');
      onProgress?.call(0.3);

      // Use pipe: zstd -d | tar
      final zstdProcess = await Process.start(
        'zstd',
        ['-d', backupPath, '--stdout'],
      );

      final tarProcess = await Process.start(
        'tar',
        ['-xf', '-'],
        workingDirectory: restoreDir,
      );

      onStatus?.call('Extracting files...');
      onProgress?.call(0.6);

      // Pipe zstd output to tar input
      zstdProcess.stdout.pipe(tarProcess.stdin);

      // Wait for both processes to complete
      final zstdExit = await zstdProcess.exitCode;
      final tarExit = await tarProcess.exitCode;

      if (zstdExit != 0) {
        final zstdError = await zstdProcess.stderr.transform(const SystemEncoding().decoder).join();
        return BackupResult(
          success: false,
          error: 'zstd decompression failed: $zstdError',
        );
      }

      if (tarExit != 0) {
        final tarError = await tarProcess.stderr.transform(const SystemEncoding().decoder).join();
        return BackupResult(
          success: false,
          error: 'tar extraction failed: $tarError',
        );
      }

      onProgress?.call(1.0);
      onStatus?.call('Restore completed successfully!');

      return BackupResult(
        success: true,
        backupPath: restoreDir,
      );
    } catch (e) {
      return BackupResult(
        success: false,
        error: 'Restore failed: $e',
      );
    }
  }

  /// Gets backup information without extracting
  /// [backupPath] - Path to the backup file (.tar.zst)
  static Future<Map<String, dynamic>> getBackupInfo(String backupPath) async {
    try {
      final backupFile = File(backupPath);
      if (!backupFile.existsSync()) {
        throw 'Backup file not found';
      }

      final stat = backupFile.statSync();
      
      // Get archive contents using zstd and tar
      final zstdProcess = await Process.start(
        'zstd',
        ['-d', backupPath, '--stdout'],
      );

      final tarProcess = await Process.start(
        'tar',
        ['-tf', '-'],
      );

      zstdProcess.stdout.pipe(tarProcess.stdin);
      
      final contentsOutput = await tarProcess.stdout.transform(const SystemEncoding().decoder).join();
      final contents = contentsOutput.trim().split('\n').where((line) => line.isNotEmpty).toList();

      await zstdProcess.exitCode;
      await tarProcess.exitCode;

      return {
        'path': backupPath,
        'size': stat.size,
        'created': stat.modified,
        'contents': contents,
        'fileCount': contents.length,
      };
    } catch (e) {
      return {
        'error': 'Failed to get backup info: $e',
      };
    }
  }

  /// Lists all backup files in a directory
  /// [backupDir] - Directory to scan for backups
  static Future<List<String>> listBackups(String backupDir) async {
    try {
      final directory = Directory(backupDir);
      if (!directory.existsSync()) {
        return [];
      }

      final files = directory.listSync()
          .where((entity) => entity is File && entity.path.endsWith(_backupExtension))
          .map((entity) => entity.path)
          .toList();

      // Sort by modification time (newest first)
      files.sort((a, b) {
        final statA = File(a).statSync();
        final statB = File(b).statSync();
        return statB.modified.compareTo(statA.modified);
      });

      return files;
    } catch (e) {
      return [];
    }
  }

  /// Gets the common parent directory for a list of paths
  static String _getCommonParentDirectory(List<String> paths) {
    if (paths.isEmpty) return '/';
    if (paths.length == 1) return p.dirname(paths.first);

    String commonPath = p.dirname(paths.first);
    
    for (int i = 1; i < paths.length; i++) {
      final currentDir = p.dirname(paths[i]);
      while (!currentDir.startsWith(commonPath) && commonPath != '/') {
        commonPath = p.dirname(commonPath);
      }
    }

    return commonPath.isEmpty ? '/' : commonPath;
  }

  /// Formats file size in human readable format
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
