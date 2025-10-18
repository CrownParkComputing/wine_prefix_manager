import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;

class FileOperationResult {
  final bool success;
  final String? error;
  final List<String> processedFiles;
  final int totalFiles;

  FileOperationResult({
    required this.success,
    this.error,
    this.processedFiles = const [],
    this.totalFiles = 0,
  });
}

class FileOperationsService {
  // Copy files/directories from source to destination
  static Future<FileOperationResult> copyFiles(
    List<String> sourcePaths,
    String destinationPath,
    Function(double progress, String currentFile)? onProgress,
  ) async {
    final processedFiles = <String>[];
    int totalFiles = 0;
    int processedCount = 0;

    try {
      // First pass: count total files
      for (final sourcePath in sourcePaths) {
        totalFiles += await _countFiles(sourcePath);
      }

      // Second pass: copy files
      for (final sourcePath in sourcePaths) {
        final sourceEntity = FileSystemEntity.isDirectorySync(sourcePath) 
            ? Directory(sourcePath) 
            : File(sourcePath);
        
        final sourceName = p.basename(sourcePath);
        final destPath = p.join(destinationPath, sourceName);

        if (sourceEntity is Directory) {
          await _copyDirectory(sourcePath, destPath, (file) {
            processedCount++;
            processedFiles.add(file);
            onProgress?.call(processedCount / totalFiles, file);
          });
        } else if (sourceEntity is File) {
          await _copyFile(sourcePath, destPath);
          processedCount++;
          processedFiles.add(sourcePath);
          onProgress?.call(processedCount / totalFiles, sourcePath);
        }
      }

      return FileOperationResult(
        success: true,
        processedFiles: processedFiles,
        totalFiles: totalFiles,
      );
    } catch (e) {
      return FileOperationResult(
        success: false,
        error: e.toString(),
        processedFiles: processedFiles,
        totalFiles: totalFiles,
      );
    }
  }

  // Move files/directories from source to destination
  static Future<FileOperationResult> moveFiles(
    List<String> sourcePaths,
    String destinationPath,
    Function(double progress, String currentFile)? onProgress,
  ) async {
    try {
      // First try rename/move (faster if on same filesystem)
      final processedFiles = <String>[];
      int processedCount = 0;

      for (final sourcePath in sourcePaths) {
        final sourceName = p.basename(sourcePath);
        final destPath = p.join(destinationPath, sourceName);

        try {
          FileSystemEntity.isDirectorySync(sourcePath)
              ? Directory(sourcePath).rename(destPath)
              : File(sourcePath).rename(destPath);
          
          processedFiles.add(sourcePath);
          processedCount++;
          onProgress?.call(processedCount / sourcePaths.length, sourcePath);
        } catch (e) {
          // If rename fails, fall back to copy + delete
          final copyResult = await copyFiles([sourcePath], destinationPath, null);
          if (copyResult.success) {
            await _deleteFileOrDirectory(sourcePath);
            processedFiles.add(sourcePath);
            processedCount++;
            onProgress?.call(processedCount / sourcePaths.length, sourcePath);
          } else {
            throw Exception('Failed to move $sourcePath: ${copyResult.error}');
          }
        }
      }

      return FileOperationResult(
        success: true,
        processedFiles: processedFiles,
        totalFiles: sourcePaths.length,
      );
    } catch (e) {
      return FileOperationResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  // Delete files/directories
  static Future<FileOperationResult> deleteFiles(
    List<String> paths,
    Function(double progress, String currentFile)? onProgress,
  ) async {
    final processedFiles = <String>[];
    int processedCount = 0;

    try {
      for (final path in paths) {
        await _deleteFileOrDirectory(path);
        processedFiles.add(path);
        processedCount++;
        onProgress?.call(processedCount / paths.length, path);
      }

      return FileOperationResult(
        success: true,
        processedFiles: processedFiles,
        totalFiles: paths.length,
      );
    } catch (e) {
      return FileOperationResult(
        success: false,
        error: e.toString(),
        processedFiles: processedFiles,
        totalFiles: paths.length,
      );
    }
  }

  // Create directory
  static Future<FileOperationResult> createDirectory(String path) async {
    try {
      await Directory(path).create(recursive: true);
      return FileOperationResult(success: true);
    } catch (e) {
      return FileOperationResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  // Rename file or directory
  static Future<FileOperationResult> renameFileOrDirectory(
    String oldPath,
    String newName,
  ) async {
    try {
      final parent = p.dirname(oldPath);
      final newPath = p.join(parent, newName);
      
      if (FileSystemEntity.isDirectorySync(oldPath)) {
        await Directory(oldPath).rename(newPath);
      } else {
        await File(oldPath).rename(newPath);
      }

      return FileOperationResult(success: true);
    } catch (e) {
      return FileOperationResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  // Get file/directory properties
  static Future<Map<String, dynamic>> getProperties(String path) async {
    try {
      final entity = FileSystemEntity.isDirectorySync(path)
          ? Directory(path)
          : File(path);
      
      final stat = await entity.stat();
      final isDirectory = entity is Directory;
      
      Map<String, dynamic> properties = {
        'path': path,
        'name': p.basename(path),
        'isDirectory': isDirectory,
        'size': isDirectory ? await _calculateDirectorySize(path) : stat.size,
        'modified': stat.modified,
        'accessed': stat.accessed,
        'changed': stat.changed,
        'mode': stat.modeString(),
        'type': stat.type,
      };

      if (isDirectory) {
        final dir = Directory(path);
        final entities = await dir.list().toList();
        properties['itemCount'] = entities.length;
        properties['fileCount'] = entities.whereType<File>().length;
        properties['directoryCount'] = entities.whereType<Directory>().length;
      }

      return properties;
    } catch (e) {
      throw Exception('Failed to get properties: $e');
    }
  }

  // Organize files into folders by type
  static Future<FileOperationResult> organizeFilesByType(
    String directoryPath,
    Function(double progress, String currentFile)? onProgress,
  ) async {
    try {
      final directory = Directory(directoryPath);
      final files = await directory
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();

      final processedFiles = <String>[];
      int processedCount = 0;

      // Group files by extension
      final Map<String, List<File>> filesByType = {};
      for (final file in files) {
        final ext = p.extension(file.path).toLowerCase();
        final category = _getFileCategory(ext);
        filesByType.putIfAbsent(category, () => []).add(file);
      }

      // Create folders and move files
      for (final entry in filesByType.entries) {
        final categoryFolder = p.join(directoryPath, entry.key);
        await Directory(categoryFolder).create(recursive: true);

        for (final file in entry.value) {
          final newPath = p.join(categoryFolder, p.basename(file.path));
          await file.rename(newPath);
          processedFiles.add(file.path);
          processedCount++;
          onProgress?.call(processedCount / files.length, file.path);
        }
      }

      return FileOperationResult(
        success: true,
        processedFiles: processedFiles,
        totalFiles: files.length,
      );
    } catch (e) {
      return FileOperationResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  // Helper methods
  static Future<int> _countFiles(String path) async {
    if (FileSystemEntity.isDirectorySync(path)) {
      int count = 0;
      final dir = Directory(path);
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) count++;
      }
      return count;
    } else {
      return 1;
    }
  }

  static Future<void> _copyDirectory(
    String sourcePath,
    String destPath,
    Function(String file) onFileProcessed,
  ) async {
    final sourceDir = Directory(sourcePath);
    await Directory(destPath).create(recursive: true);

    await for (final entity in sourceDir.list(recursive: false)) {
      final entityName = p.basename(entity.path);
      final destEntityPath = p.join(destPath, entityName);

      if (entity is Directory) {
        await _copyDirectory(entity.path, destEntityPath, onFileProcessed);
      } else if (entity is File) {
        await _copyFile(entity.path, destEntityPath);
        onFileProcessed(entity.path);
      }
    }
  }

  static Future<void> _copyFile(String sourcePath, String destPath) async {
    final sourceFile = File(sourcePath);
    final destFile = File(destPath);

    final sourceStream = sourceFile.openRead();
    final destSink = destFile.openWrite();

    await sourceStream.pipe(destSink);
    await destSink.close();

    // Preserve timestamps
    final sourceStat = await sourceFile.stat();
    await destFile.setLastModified(sourceStat.modified);
  }

  static Future<void> _deleteFileOrDirectory(String path) async {
    if (FileSystemEntity.isDirectorySync(path)) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  static Future<int> _calculateDirectorySize(String path) async {
    int totalSize = 0;
    final dir = Directory(path);

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final stat = await entity.stat();
        totalSize += stat.size;
      }
    }

    return totalSize;
  }

  static String _getFileCategory(String extension) {
    switch (extension) {
      case '.exe':
      case '.msi':
      case '.bat':
      case '.cmd':
        return 'Executables';
      case '.dll':
      case '.so':
      case '.dylib':
        return 'Libraries';
      case '.txt':
      case '.log':
      case '.cfg':
      case '.ini':
      case '.conf':
        return 'Text Files';
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.bmp':
      case '.gif':
      case '.tiff':
        return 'Images';
      case '.mp3':
      case '.wav':
      case '.ogg':
      case '.flac':
        return 'Audio';
      case '.mp4':
      case '.avi':
      case '.mkv':
      case '.mov':
        return 'Videos';
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
        return 'Archives';
      case '.pdf':
      case '.doc':
      case '.docx':
      case '.rtf':
        return 'Documents';
      default:
        return extension.isEmpty ? 'Other' : '${extension.substring(1).toUpperCase()} Files';
    }
  }
}