import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;

class ArchiveResult {
  final bool success;
  final String? outputPath;
  final String? error;
  final List<String> extractedFiles;

  ArchiveResult({
    required this.success,
    this.outputPath,
    this.error,
    this.extractedFiles = const [],
  });
}

class ArchiveService {
  /// Extracts various archive formats
  /// [archivePath] - Path to the archive file
  /// [extractToDir] - Directory where files will be extracted
  /// [onProgress] - Optional callback for progress updates (0.0 to 1.0)
  /// [onStatus] - Optional callback for status messages
  static Future<ArchiveResult> extractArchive({
    required String archivePath,
    required String extractToDir,
    Function(double)? onProgress,
    Function(String)? onStatus,
  }) async {
    try {
      final archiveFile = File(archivePath);
      if (!archiveFile.existsSync()) {
        return ArchiveResult(
          success: false,
          error: 'Archive file not found: $archivePath',
        );
      }

      // Ensure extraction directory exists
      final extractDir = Directory(extractToDir);
      if (!extractDir.existsSync()) {
        extractDir.createSync(recursive: true);
      }

      final extension = p.extension(archivePath).toLowerCase();
      final archiveName = p.basenameWithoutExtension(archivePath);

      onStatus?.call('Analyzing archive...');
      onProgress?.call(0.1);

      // Determine archive type and extract accordingly
      switch (extension) {
        case '.zip':
          return await _extractZip(archivePath, extractToDir, archiveName, onProgress, onStatus);
        case '.rar':
          return await _extractRar(archivePath, extractToDir, archiveName, onProgress, onStatus);
        case '.7z':
          return await _extract7z(archivePath, extractToDir, archiveName, onProgress, onStatus);
        case '.tar':
        case '.gz':
        case '.bz2':
        case '.xz':
        case '.zst':
          return await _extractTar(archivePath, extractToDir, archiveName, onProgress, onStatus);
        default:
          // Try to detect by file content/magic numbers
          return await _extractGeneric(archivePath, extractToDir, archiveName, onProgress, onStatus);
      }
    } catch (e) {
      return ArchiveResult(
        success: false,
        error: 'Extraction failed: $e',
      );
    }
  }

  /// Creates ZIP archives
  static Future<ArchiveResult> createZip({
    required List<String> sourcePaths,
    required String outputPath,
    Function(double)? onProgress,
    Function(String)? onStatus,
  }) async {
    try {
      // Check if zip is available
      final zipCheck = await Process.run('which', ['zip']);
      if (zipCheck.exitCode != 0) {
        return ArchiveResult(
          success: false,
          error: 'zip tool not found. Please install zip package.',
        );
      }

      onStatus?.call('Analyzing files...');
      onProgress?.call(0.1);

      // Count total files for progress tracking
      int totalFiles = 0;
      for (final sourcePath in sourcePaths) {
        final entity = FileSystemEntity.isDirectorySync(sourcePath) 
            ? Directory(sourcePath) 
            : File(sourcePath);
        if (entity is Directory) {
          totalFiles += await entity.list(recursive: true).where((e) => e is File).length;
        } else {
          totalFiles++;
        }
      }

      onStatus?.call('Creating ZIP archive ($totalFiles files)...');
      onProgress?.call(0.2);

      // Get common parent directory
      final workingDir = _getCommonParentDirectory(sourcePaths);
      final relativePaths = sourcePaths.map((path) => p.relative(path, from: workingDir)).toList();

      // Start ZIP process with verbose output
      final process = await Process.start(
        'zip',
        ['-r', '-v', outputPath, ...relativePaths],
        workingDirectory: workingDir,
      );

      int processedFiles = 0;
      await for (final line in process.stdout.transform(const SystemEncoding().decoder).transform(const LineSplitter())) {
        if (line.trim().startsWith('adding:') || line.trim().startsWith('deflating:')) {
          processedFiles++;
          final progress = 0.2 + (processedFiles / totalFiles) * 0.7;
          onProgress?.call(progress.clamp(0.2, 0.9));
          
          final fileName = line.split(':').length > 1 ? line.split(':')[1].trim() : 'file';
          onStatus?.call('Adding: ${p.basename(fileName)} ($processedFiles/$totalFiles)');
        }
      }

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        final errorOutput = await process.stderr.transform(const SystemEncoding().decoder).join();
        return ArchiveResult(
          success: false,
          error: 'ZIP creation failed: $errorOutput',
        );
      }

      onProgress?.call(1.0);
      onStatus?.call('ZIP archive created successfully! ($processedFiles files)');

      return ArchiveResult(
        success: true,
        outputPath: outputPath,
      );
    } catch (e) {
      return ArchiveResult(
        success: false,
        error: 'ZIP creation failed: $e',
      );
    }
  }

  /// Creates RAR archives
  static Future<ArchiveResult> createRar({
    required List<String> sourcePaths,
    required String outputPath,
    Function(double)? onProgress,
    Function(String)? onStatus,
  }) async {
    try {
      // Check if rar is available
      final rarCheck = await Process.run('which', ['rar']);
      if (rarCheck.exitCode != 0) {
        return ArchiveResult(
          success: false,
          error: 'rar tool not found. Please install rar package.',
        );
      }

      onStatus?.call('Analyzing files...');
      onProgress?.call(0.1);

      // Count total files for progress tracking
      int totalFiles = 0;
      for (final sourcePath in sourcePaths) {
        final entity = FileSystemEntity.isDirectorySync(sourcePath) 
            ? Directory(sourcePath) 
            : File(sourcePath);
        if (entity is Directory) {
          totalFiles += await entity.list(recursive: true).where((e) => e is File).length;
        } else {
          totalFiles++;
        }
      }

      onStatus?.call('Creating RAR archive ($totalFiles files)...');
      onProgress?.call(0.2);

      final workingDir = _getCommonParentDirectory(sourcePaths);
      final relativePaths = sourcePaths.map((path) => p.relative(path, from: workingDir)).toList();

      // Start RAR process
      final process = await Process.start(
        'rar',
        ['a', '-r', '-ep1', outputPath, ...relativePaths],
        workingDirectory: workingDir,
      );

      int processedFiles = 0;
      await for (final line in process.stdout.transform(const SystemEncoding().decoder).transform(const LineSplitter())) {
        if (line.trim().startsWith('Adding') || line.contains('%')) {
          processedFiles++;
          final progress = 0.2 + (processedFiles / totalFiles) * 0.7;
          onProgress?.call(progress.clamp(0.2, 0.9));
          
          // Extract filename from RAR output
          String fileName = 'file';
          if (line.contains('Adding')) {
            final parts = line.split('Adding');
            if (parts.length > 1) {
              fileName = parts[1].trim();
            }
          }
          onStatus?.call('Adding: ${p.basename(fileName)} ($processedFiles/$totalFiles)');
        }
      }

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        final errorOutput = await process.stderr.transform(const SystemEncoding().decoder).join();
        return ArchiveResult(
          success: false,
          error: 'RAR creation failed: $errorOutput',
        );
      }

      onProgress?.call(1.0);
      onStatus?.call('RAR archive created successfully! ($processedFiles files)');

      return ArchiveResult(
        success: true,
        outputPath: outputPath,
      );
    } catch (e) {
      return ArchiveResult(
        success: false,
        error: 'RAR creation failed: $e',
      );
    }
  }

  // Private extraction methods
  static Future<ArchiveResult> _extractZip(String archivePath, String extractToDir, String archiveName, Function(double)? onProgress, Function(String)? onStatus) async {
    final zipCheck = await Process.run('which', ['unzip']);
    if (zipCheck.exitCode != 0) {
      return ArchiveResult(
        success: false,
        error: 'unzip tool not found. Please install unzip package.',
      );
    }

    onStatus?.call('Analyzing ZIP archive...');
    onProgress?.call(0.1);

    // First, get the file count for progress tracking
    final listResult = await Process.run('unzip', ['-l', archivePath]);
    int totalFiles = 0;
    if (listResult.exitCode == 0) {
      final lines = listResult.stdout.toString().split('\n');
      for (final line in lines) {
        if (line.trim().isNotEmpty && !line.contains('----') && !line.contains('Archive:') && !line.contains('files')) {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 4 && int.tryParse(parts[0]) != null) {
            totalFiles++;
          }
        }
      }
    }
    totalFiles = totalFiles > 0 ? totalFiles : 1; // Fallback

    onStatus?.call('Extracting ZIP archive ($totalFiles files)...');
    onProgress?.call(0.2);

    // Create subdirectory for extraction
    final targetDir = p.join(extractToDir, archiveName);
    await Directory(targetDir).create(recursive: true);

    // Start extraction process with verbose output
    final process = await Process.start(
      'unzip',
      ['-o', archivePath, '-d', targetDir],
    );

    // Monitor progress by counting output lines
    int extractedFiles = 0;
    final outputBuffer = <String>[];

    await for (final line in process.stdout.transform(const SystemEncoding().decoder).transform(const LineSplitter())) {
      outputBuffer.add(line);
      if (line.trim().startsWith('inflating:') || line.trim().startsWith('extracting:')) {
        extractedFiles++;
        final progress = 0.2 + (extractedFiles / totalFiles) * 0.7;
        onProgress?.call(progress.clamp(0.2, 0.9));
        
        final fileName = line.split(':').length > 1 ? line.split(':')[1].trim() : 'file';
        onStatus?.call('Extracting: ${p.basename(fileName)} ($extractedFiles/$totalFiles)');
      }
    }

    final exitCode = await process.exitCode;

    if (exitCode != 0) {
      final errorOutput = await process.stderr.transform(const SystemEncoding().decoder).join();
      return ArchiveResult(
        success: false,
        error: 'ZIP extraction failed: $errorOutput',
      );
    }

    onProgress?.call(1.0);
    onStatus?.call('ZIP extracted successfully! ($extractedFiles files)');

    return ArchiveResult(
      success: true,
      outputPath: targetDir,
      extractedFiles: await _listExtractedFiles(targetDir),
    );
  }

  static Future<ArchiveResult> _extractRar(String archivePath, String extractToDir, String archiveName, Function(double)? onProgress, Function(String)? onStatus) async {
    final rarCheck = await Process.run('which', ['unrar']);
    if (rarCheck.exitCode != 0) {
      return ArchiveResult(
        success: false,
        error: 'unrar tool not found. Please install unrar package.',
      );
    }

    onStatus?.call('Analyzing RAR archive...');
    onProgress?.call(0.1);

    // Get file count for progress tracking
    final listResult = await Process.run('unrar', ['l', archivePath]);
    int totalFiles = 0;
    if (listResult.exitCode == 0) {
      final lines = listResult.stdout.toString().split('\n');
      for (final line in lines) {
        if (line.trim().isNotEmpty && 
            !line.contains('----') && 
            !line.contains('Archive:') && 
            !line.contains('UNRAR') &&
            line.contains('.')) {
          // Count lines that look like file entries
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 5) {
            totalFiles++;
          }
        }
      }
    }
    totalFiles = totalFiles > 0 ? totalFiles : 1;

    onStatus?.call('Extracting RAR archive ($totalFiles files)...');
    onProgress?.call(0.2);

    final targetDir = p.join(extractToDir, archiveName);
    await Directory(targetDir).create(recursive: true);

    // Start extraction with progress monitoring
    final process = await Process.start(
      'unrar',
      ['x', '-o+', archivePath, targetDir + '/'],
    );

    int extractedFiles = 0;
    await for (final line in process.stdout.transform(const SystemEncoding().decoder).transform(const LineSplitter())) {
      if (line.trim().startsWith('Extracting') || line.contains('OK')) {
        extractedFiles++;
        final progress = 0.2 + (extractedFiles / totalFiles) * 0.7;
        onProgress?.call(progress.clamp(0.2, 0.9));
        
        // Extract filename from the line
        String fileName = 'file';
        if (line.contains('Extracting')) {
          final parts = line.split('Extracting');
          if (parts.length > 1) {
            fileName = parts[1].trim();
          }
        }
        onStatus?.call('Extracting: ${p.basename(fileName)} ($extractedFiles/$totalFiles)');
      }
    }

    final exitCode = await process.exitCode;

    if (exitCode != 0) {
      final errorOutput = await process.stderr.transform(const SystemEncoding().decoder).join();
      return ArchiveResult(
        success: false,
        error: 'RAR extraction failed: $errorOutput',
      );
    }

    onProgress?.call(1.0);
    onStatus?.call('RAR extracted successfully! ($extractedFiles files)');

    return ArchiveResult(
      success: true,
      outputPath: targetDir,
      extractedFiles: await _listExtractedFiles(targetDir),
    );
  }

  static Future<ArchiveResult> _extract7z(String archivePath, String extractToDir, String archiveName, Function(double)? onProgress, Function(String)? onStatus) async {
    final p7zipCheck = await Process.run('which', ['7z']);
    if (p7zipCheck.exitCode != 0) {
      return ArchiveResult(
        success: false,
        error: '7z tool not found. Please install p7zip package.',
      );
    }

    onStatus?.call('Extracting 7z archive...');
    onProgress?.call(0.3);

    final targetDir = p.join(extractToDir, archiveName);
    await Directory(targetDir).create(recursive: true);

    final result = await Process.run(
      '7z',
      ['x', archivePath, '-o$targetDir', '-y'],
    );

    onProgress?.call(0.9);

    if (result.exitCode != 0) {
      return ArchiveResult(
        success: false,
        error: '7z extraction failed: ${result.stderr}',
      );
    }

    onProgress?.call(1.0);
    onStatus?.call('7z archive extracted successfully!');

    return ArchiveResult(
      success: true,
      outputPath: targetDir,
      extractedFiles: await _listExtractedFiles(targetDir),
    );
  }

  static Future<ArchiveResult> _extractTar(String archivePath, String extractToDir, String archiveName, Function(double)? onProgress, Function(String)? onStatus) async {
    onStatus?.call('Extracting tar archive...');
    onProgress?.call(0.3);

    final targetDir = p.join(extractToDir, archiveName);
    await Directory(targetDir).create(recursive: true);

    // Determine decompression method based on file extension
    List<String> tarArgs = ['-xf', archivePath, '-C', targetDir];
    
    final result = await Process.run('tar', tarArgs);

    onProgress?.call(0.9);

    if (result.exitCode != 0) {
      return ArchiveResult(
        success: false,
        error: 'Tar extraction failed: ${result.stderr}',
      );
    }

    onProgress?.call(1.0);
    onStatus?.call('Tar archive extracted successfully!');

    return ArchiveResult(
      success: true,
      outputPath: targetDir,
      extractedFiles: await _listExtractedFiles(targetDir),
    );
  }

  static Future<ArchiveResult> _extractGeneric(String archivePath, String extractToDir, String archiveName, Function(double)? onProgress, Function(String)? onStatus) async {
    // Try different tools in order of preference
    final tools = [
      {'tool': '7z', 'args': ['x', archivePath, '-o$extractToDir/$archiveName', '-y']},
      {'tool': 'unzip', 'args': ['-o', archivePath, '-d', '$extractToDir/$archiveName']},
      {'tool': 'tar', 'args': ['-xf', archivePath, '-C', '$extractToDir/$archiveName']},
    ];

    onStatus?.call('Detecting archive format...');
    onProgress?.call(0.1);

    for (final toolConfig in tools) {
      final tool = toolConfig['tool'] as String;
      final args = toolConfig['args'] as List<String>;

      final toolCheck = await Process.run('which', [tool]);
      if (toolCheck.exitCode == 0) {
        try {
          onStatus?.call('Extracting with $tool...');
          onProgress?.call(0.3);

          final targetDir = p.join(extractToDir, archiveName);
          await Directory(targetDir).create(recursive: true);

          final result = await Process.run(tool, args);

          if (result.exitCode == 0) {
            onProgress?.call(1.0);
            onStatus?.call('Archive extracted successfully with $tool!');
            return ArchiveResult(
              success: true,
              outputPath: targetDir,
              extractedFiles: await _listExtractedFiles(targetDir),
            );
          }
        } catch (e) {
          // Try next tool
          continue;
        }
      }
    }

    return ArchiveResult(
      success: false,
      error: 'No suitable extraction tool found or archive format not supported.',
    );
  }

  static Future<List<String>> _listExtractedFiles(String directory) async {
    try {
      final dir = Directory(directory);
      final files = <String>[];
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          files.add(entity.path);
        }
      }
      return files;
    } catch (e) {
      return [];
    }
  }

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

  /// Checks if a file is a supported archive format
  static bool isArchiveFile(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    return ['.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.zst'].contains(extension);
  }

  /// Gets list of supported archive formats
  static List<String> getSupportedFormats() {
    return ['.zip', '.rar', '.7z', '.tar', '.tar.gz', '.tar.bz2', '.tar.xz', '.tar.zst'];
  }
}