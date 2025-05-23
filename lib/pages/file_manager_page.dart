import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/settings.dart';
import '../models/prefix_models.dart';
import '../providers/prefix_provider.dart';

// Utility to sanitize file-/folder names
String sanitizeFileName(String name) {
  return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(RegExp(r'\s+'), '_');
}

class FileManagerPage extends StatefulWidget {
  final GameEntry? game;

  const FileManagerPage({Key? key, this.game}) : super(key: key);

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  // Game selection and folder paths
  String sourceFolderPath = '';
  String backupFolderPath = '';
  List<String> saveDataPaths = []; // Multiple save data paths
  bool loading = true;
  String error = '';
  List<GameEntry> availableGames = [];
  GameEntry? selectedGame;

  // Backup folder navigation
  List<String> pathHistory = [];
  List<FileSystemEntity> backupEntries = [];
  bool loadingBackups = false;

  // Backup options
  int compressionLevel = 3;
  int compressionThreads = 0; // 0 means auto (use all available)
  bool includeGameSaves = true;
  bool includeConfigs = true;
  bool backupInProgress = false;
  double backupProgress = 0.0;
  String backupStatus = '';
  int totalFileSize = 0;
  int processedFileSize = 0;

  @override
  void initState() {
    super.initState();
    selectedGame = widget.game;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAvailableGames();
    });
  }

  void _loadAvailableGames() {
    setState(() => loading = true);

    final prefixProvider = Provider.of<PrefixProvider>(context, listen: false);
    final games = prefixProvider.getAllGamesFromPrefixes();

    setState(() {
      availableGames = games;

      if (selectedGame == null && games.isNotEmpty) {
        selectedGame = games.first;
      }

      _initializeDirectories();
    });
  }

  void _initializeDirectories() {
    if (selectedGame != null) {
      // Auto-set source folder to game directory
      sourceFolderPath = p.dirname(selectedGame!.exe.path);
      
      // Auto-discover save data folders
      _autoDiscoverSaveDataFolders();
    }

    // Set default backup folder path
    final settings = Provider.of<Settings>(context, listen: false);
    backupFolderPath = p.join(settings.backupPath ?? settings.prefixDirectory, 'game_backups');

    setState(() => loading = false);
    _refreshBackupEntries();
  }

  void _autoDiscoverSaveDataFolders() {
    if (selectedGame == null) return;
    
    final List<String> potentialSavePaths = [];
    final prefix = selectedGame!.prefix;
    
    // Check common save locations
    final List<String> commonSaveFolders = [
      'drive_c/users/*/Documents/My Games',
      'drive_c/users/*/Documents/Games', 
      'drive_c/users/*/Documents/${selectedGame!.exe.name}',
      'drive_c/users/*/AppData/Local/${selectedGame!.exe.name}',
      'drive_c/users/*/AppData/Roaming/${selectedGame!.exe.name}',
      'drive_c/users/*/Saved Games',
    ];
    
    for (final pattern in commonSaveFolders) {
      final fullPath = p.join(prefix.path, pattern);
      final parts = fullPath.split('*');
      
      if (parts.length == 2) {
        try {
          final dir = Directory(parts[0]);
          if (dir.existsSync()) {
            final userDirs = dir.listSync().whereType<Directory>();
            for (final userDir in userDirs) {
              final savePath = p.join(userDir.path, parts[1].substring(1)); // Remove leading /
              if (Directory(savePath).existsSync()) {
                potentialSavePaths.add(savePath);
              }
            }
          }
        } catch (e) {
          // Ignore errors in auto-discovery
        }
      } else {
        if (Directory(fullPath).existsSync()) {
          potentialSavePaths.add(fullPath);
        }
      }
    }
    
    setState(() {
      saveDataPaths = potentialSavePaths;
    });
  }

  Future<void> _selectSourceFolder() async {
    if (selectedGame == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a game first')),
        );
      }
      return;
    }

    // Default to the parent directory of the game executable
    String initialDir = p.dirname(selectedGame!.exe.path);

    final String? selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Game Folder to Backup',
      initialDirectory: initialDir,
    );

    if (selectedDir != null) {
      setState(() {
        sourceFolderPath = selectedDir;
      });
    }
  }

  Future<void> _addSaveDataFolder() async {
    if (selectedGame == null) return;

    // Default to Documents folder in the wine prefix
    final prefix = selectedGame!.prefix;
    String initialDir = p.join(prefix.path, 'drive_c/users');
    
    // Try to find the first user directory
    try {
      final usersDir = Directory(initialDir);
      if (usersDir.existsSync()) {
        final userDirs = usersDir.listSync().whereType<Directory>().toList();
        if (userDirs.isNotEmpty) {
          final firstUser = userDirs.firstWhere(
            (dir) => p.basename(dir.path) != 'Public',
            orElse: () => userDirs.first,
          );
          final documentsDir = p.join(firstUser.path, 'Documents');
          if (Directory(documentsDir).existsSync()) {
            initialDir = documentsDir;
          }
        }
      }
    } catch (e) {
      // Use default if there's an error
    }

    final String? selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Save Data Folder',
      initialDirectory: initialDir,
    );

    if (selectedDir != null && !saveDataPaths.contains(selectedDir)) {
      setState(() {
        saveDataPaths.add(selectedDir);
      });
    }
  }

  void _removeSaveDataFolder(String path) {
    setState(() {
      saveDataPaths.remove(path);
    });
  }

  Future<int> _calculateTotalSize(List<String> paths) async {
    int totalSize = 0;
    
    for (final path in paths) {
      if (Directory(path).existsSync()) {
        totalSize += await _calculateDirectorySize(Directory(path));
      }
    }
    
    return totalSize;
  }

  Future<int> _calculateDirectorySize(Directory dir) async {
    int size = 0;
    
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            size += await entity.length();
          } catch (e) {
            // Ignore inaccessible files
          }
        }
      }
    } catch (e) {
      // Ignore errors
    }
    
    return size;
  }

  Future<void> _refreshBackupEntries() async {
    if (backupFolderPath.isEmpty) return;

    setState(() {
      loadingBackups = true;
      error = '';
    });

    try {
      final dir = Directory(backupFolderPath);

      // Create directory if it doesn't exist
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final entitiesList = await dir.list().toList();

      // Filter and sort entries
      backupEntries = entitiesList.where((e) {
        final name = p.basename(e.path);
        return !name.startsWith('.');
      }).toList();

      // Sort: directories first, then files
      backupEntries.sort((a, b) {
        bool aIsDir = FileSystemEntity.isDirectorySync(a.path);
        bool bIsDir = FileSystemEntity.isDirectorySync(b.path);

        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;

        return p.basename(a.path).compareTo(p.basename(b.path));
      });
    } catch (e) {
      setState(() {
        error = 'Error accessing directory: $e';
      });
    } finally {
      setState(() {
        loadingBackups = false;
      });
    }
  }

  Future<void> _navigateToDirectory(String path) async {
    pathHistory.add(backupFolderPath);
    setState(() {
      backupFolderPath = path;
    });
    await _refreshBackupEntries();
  }

  Future<void> _navigateUp() async {
    final parentDir = p.dirname(backupFolderPath);
    if (parentDir != backupFolderPath) {
      pathHistory.add(backupFolderPath);
      setState(() {
        backupFolderPath = parentDir;
      });
      await _refreshBackupEntries();
    }
  }

  Future<void> _navigateBack() async {
    if (pathHistory.isNotEmpty) {
      final previousPath = pathHistory.removeLast();
      setState(() {
        backupFolderPath = previousPath;
      });
      await _refreshBackupEntries();
    }
  }

  Future<void> _createBackup() async {
    if (sourceFolderPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a game folder first')),
      );
      return;
    }

    // Prepare list of all paths to backup
    final List<String> pathsToBackup = [sourceFolderPath];
    pathsToBackup.addAll(saveDataPaths);

    final folderName = p.basename(sourceFolderPath);
    final timestamp = DateTime.now()
        .toString()
        .replaceAll(':', '-')
        .replaceAll(' ', '_')
        .split('.')
        .first;
    final backupName = '${folderName}_$timestamp.tar.zst';
    final outputPath = p.join(backupFolderPath, backupName);

    setState(() {
      backupInProgress = true;
      backupProgress = 0.0;
      backupStatus = 'Calculating backup size...';
      processedFileSize = 0;
    });

    try {
      // Calculate total size for progress tracking
      totalFileSize = await _calculateTotalSize(pathsToBackup);
      
      setState(() {
        backupStatus = 'Creating backup archive...';
      });

      // Create temporary script to handle multiple paths and progress
      final tempDir = Directory.systemTemp.createTempSync('backup_');
      final scriptPath = p.join(tempDir.path, 'backup_script.sh');
      
      // Build exclude list
      List<String> excludes = ['--exclude=*.lock', '--exclude=*/tmp/*', '--exclude=*/cache/*'];

      if (!includeGameSaves) {
        excludes.addAll(['--exclude=*/saves/*', '--exclude=*/Saves/*']);
      }

      if (!includeConfigs) {
        excludes.addAll(['--exclude=*/config/*', '--exclude=*.ini', '--exclude=*.cfg']);
      }

      // Create backup script that handles multiple directories
      String scriptContent = '''#!/bin/bash
set -e

# Function to add directory to tar if it exists
add_to_tar() {
    local path="\$1"
    local base_name="\$2"
    if [ -d "\$path" ]; then
        echo "Adding: \$path"
        tar rf "\$temp_tar" -C "\$(dirname "\$path")" ${excludes.join(' ')} "\$base_name" 2>/dev/null || true
    fi
}

temp_tar="${tempDir.path}/backup.tar"
rm -f "\$temp_tar"

# Add main game folder
add_to_tar "$sourceFolderPath" "${p.basename(sourceFolderPath)}"

''';

      // Add save data folders to script
      for (final savePath in saveDataPaths) {
        final relativePath = p.relative(savePath, from: p.dirname(savePath));
        scriptContent += '''
# Add save data folder
add_to_tar "$savePath" "$relativePath"

''';
      }

      // Complete script with compression
      scriptContent += '''
# Compress with progress monitoring
echo "Compressing archive..."
pv "\$temp_tar" | zstd -$compressionLevel --threads=$compressionThreads > "$outputPath"

# Cleanup
rm -f "\$temp_tar"
echo "Backup complete!"
''';

      // Write script
      await File(scriptPath).writeAsString(scriptContent);
      await Process.run('chmod', ['+x', scriptPath]);

      // Start backup process
      final process = await Process.start('bash', [scriptPath]);

      // Monitor progress using file size
      Timer.periodic(const Duration(milliseconds: 500), (timer) async {
        if (!backupInProgress) {
          timer.cancel();
          return;
        }

        try {
          final outputFile = File(outputPath);
          if (await outputFile.exists()) {
            final currentSize = await outputFile.length();
            // Estimate progress based on compression ratio (rough estimate)
            final estimatedProgress = (currentSize * 3) / totalFileSize; // Assume 3:1 compression
            setState(() {
              backupProgress = estimatedProgress.clamp(0.0, 0.95); // Don't show 100% until done
              backupStatus = 'Creating backup... ${(backupProgress * 100).toStringAsFixed(1)}%';
            });
          }
        } catch (e) {
          // Ignore errors during progress monitoring
        }
      });

      // Listen to process output
      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        debugPrint('Backup output: $data');
        if (mounted) {
          setState(() {
            backupStatus = data.trim().isNotEmpty ? data.trim() : backupStatus;
          });
        }
      });

      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        debugPrint('Backup error: $data');
      });

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        throw Exception('Backup process failed with exit code $exitCode');
      }

      setState(() {
        backupProgress = 1.0;
        backupStatus = 'Backup completed successfully!';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup created: $backupName')),
        );
      }

      // Cleanup temp directory
      await tempDir.delete(recursive: true);
      await _refreshBackupEntries();

    } catch (e) {
      setState(() {
        error = 'Backup error: $e';
        backupStatus = 'Backup failed: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating backup: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        backupInProgress = false;
      });
    }
  }

  Future<void> _decompressFile(String filePath) async {
    // Ask for destination directory
    final String? destinationDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Where to Extract',
      initialDirectory: p.dirname(filePath),
    );

    if (destinationDir == null) return;

    setState(() {
      backupInProgress = true;
      backupProgress = 0.0;
    });

    try {
      final fileName = p.basename(filePath);

      // Create command based on file type
      String cmd;
      if (fileName.endsWith('.tar.zst')) {
        cmd = 'pv -n "$filePath" | zstd -d --threads=$compressionThreads | tar xf - -C "$destinationDir"';
      } else if (fileName.endsWith('.zst')) {
        final outFile = p.join(destinationDir, p.basenameWithoutExtension(fileName));
        cmd = 'pv -n "$filePath" | zstd -d --threads=$compressionThreads > "$outFile"';
      } else {
        throw Exception('Unsupported file format');
      }

      final process = await Process.start('sh', ['-c', cmd]);

      // Listen to stderr for pv progress
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        try {
          final progress = double.parse(data.trim()) / 100.0;
          setState(() {
            backupProgress = progress.clamp(0.0, 1.0);
          });
        } catch (_) {}
      });

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        throw Exception('Extraction failed with exit code $exitCode');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File extracted to $destinationDir')),
      );
    } catch (e) {
      setState(() {
        error = 'Extraction error: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error extracting file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        backupInProgress = false;
      });
    }
  }

  Future<void> _deleteEntry(String path) async {
    final fileName = p.basename(path);
    final isDirectory = FileSystemEntity.isDirectorySync(path);

    // Confirm deletion
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${isDirectory ? 'Folder' : 'File'}'),
        content: Text('Are you sure you want to delete "$fileName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (isDirectory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $fileName')),
      );

      await _refreshBackupEntries();
    } catch (e) {
      setState(() {
        error = 'Delete error: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting $fileName: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getFileInfo(FileSystemEntity entity) {
    try {
      if (FileSystemEntity.isDirectorySync(entity.path)) {
        return 'Directory';
      } else {
        final file = File(entity.path);
        final size = file.lengthSync();

        if (size < 1024) {
          return '$size bytes';
        } else if (size < 1024 * 1024) {
          return '${(size / 1024).toStringAsFixed(1)} KB';
        } else if (size < 1024 * 1024 * 1024) {
          return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
        } else {
          return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
        }
      }
    } catch (e) {
      return 'Error: $e';
    }
  }

  IconData _getFileIcon(String path) {
    final extension = p.extension(path).toLowerCase();

    switch (extension) {
      case '.exe':
        return Icons.videogame_asset;
      case '.dll':
        return Icons.integration_instructions;
      case '.txt':
      case '.log':
        return Icons.description;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
        return Icons.image;
      case '.ini':
      case '.cfg':
      case '.conf':
        return Icons.settings;
      case '.zst':
        return Icons.archive;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Backup Manager${selectedGame != null ? ' - ${selectedGame!.exe.name}' : ''}'),
        actions: [
          if (availableGames.isNotEmpty)
            PopupMenuButton<GameEntry>(
              tooltip: 'Select Game',
              icon: const Icon(Icons.sports_esports),
              enabled: !backupInProgress,
              onSelected: (game) {
                setState(() {
                  selectedGame = game;
                  sourceFolderPath = p.dirname(game.exe.path);
                  _autoDiscoverSaveDataFolders();
                });
              },
              itemBuilder: (context) {
                return availableGames.map((game) {
                  return PopupMenuItem<GameEntry>(
                    value: game,
                    child: Text(game.exe.name),
                  );
                }).toList();
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: backupInProgress ? null : _refreshBackupEntries,
          ),
        ],
      ),
      body: Column(
        children: [
          // Top half - Game folder selection and backup options
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Game selection
                if (selectedGame != null)
                  Text(
                    'Game: ${selectedGame!.exe.name}',
                    style: theme.textTheme.titleMedium,
                  )
                else
                  const Text(
                    'Select a game to begin',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                const SizedBox(height: 16),

                // Source folder selection
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Source Folder:',
                              style: theme.textTheme.bodySmall,
                            ),
                            Text(
                              sourceFolderPath.isEmpty ? 'No folder selected' : sourceFolderPath,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: sourceFolderPath.isEmpty ? FontWeight.normal : FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Browse'),
                      onPressed: backupInProgress ? null : _selectSourceFolder,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Save data folders section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Save Data Folders:',
                      style: theme.textTheme.titleSmall,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add Save Folder'),
                      onPressed: (selectedGame != null && !backupInProgress) ? _addSaveDataFolder : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // List of save data folders
                if (saveDataPaths.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(4),
                      color: theme.colorScheme.surface.withValues(alpha: 0.5),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No save data folders selected. Use "Add Save Folder" to include save files in the backup.',
                            style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: saveDataPaths.length,
                      itemBuilder: (context, index) {
                        final path = saveDataPaths[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.save, size: 16),
                          title: Text(
                            p.basename(path),
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            path,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 18),
                            onPressed: backupInProgress ? null : () => _removeSaveDataFolder(path),
                            tooltip: 'Remove this save folder',
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),

                // Backup options
                Text(
                  'Backup Options:',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),

                // Compression level slider
                Row(
                  children: [
                    const Text('Compression:'),
                    Expanded(
                      child: Slider(
                        value: compressionLevel.toDouble(),
                        min: 1,
                        max: 19,
                        divisions: 18,
                        label: compressionLevel.toString(),
                        onChanged: backupInProgress ? null : (value) { // Disable during backup
                          setState(() {
                            compressionLevel = value.round();
                          });
                        },
                      ),
                    ),
                    Text(
                      "$compressionLevel",
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),

                // Thread count slider
                Row(
                  children: [
                    const Text('Threads:'),
                    Expanded(
                      child: Slider(
                        value: compressionThreads.toDouble(),
                        min: 0,
                        max: 16,
                        divisions: 16,
                        label: compressionThreads == 0 ? "Auto" : compressionThreads.toString(),
                        onChanged: backupInProgress ? null : (value) { // Disable during backup
                          setState(() {
                            compressionThreads = value.round();
                          });
                        },
                      ),
                    ),
                    Text(
                      compressionThreads == 0 ? "Auto" : "$compressionThreads",
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),

                // Thread explanation text
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    compressionThreads == 0
                        ? 'Using all available CPU threads for compression'
                        : 'Using $compressionThreads thread${compressionThreads > 1 ? "s" : ""} for compression',
                    style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ),

                // Include options
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Include saves'),
                        value: includeGameSaves,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: backupInProgress ? null : (value) { // Disable during backup
                          setState(() {
                            includeGameSaves = value ?? true;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Include configs'),
                        value: includeConfigs,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: backupInProgress ? null : (value) { // Disable during backup
                          setState(() {
                            includeConfigs = value ?? true;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Create backup button
                Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.backup),
                    label: const Text('Create Backup'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: sourceFolderPath.isEmpty || backupInProgress ? null : _createBackup,
                  ),
                ),

                // Progress indicator
                if (backupInProgress)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        backupStatus,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: backupProgress > 0 ? backupProgress : null,
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Divider between sections
          const Divider(height: 1),

          // Backup folder navigation
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Parent Directory',
                  onPressed: (backupInProgress) ? null : _navigateUp, // Disable during operations
                ),
                if (pathHistory.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Go Back',
                    onPressed: (backupInProgress) ? null : _navigateBack, // Disable during operations
                  ),
                Expanded(
                  child: Text(
                    backupFolderPath,
                    style: const TextStyle(fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Error display
          if (error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => error = ''),
                  ),
                ],
              ),
            ),

          // Bottom half - Backup files listing
          Expanded(
            child: (backupInProgress) 
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Creating backup...',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  )
                : loadingBackups
                    ? const Center(child: CircularProgressIndicator())
                    : backupEntries.isEmpty
                        ? const Center(
                            child: Text('No backups found'),
                          )
                        : ListView.builder(
                            itemCount: backupEntries.length,
                            itemBuilder: (context, index) {
                              final entry = backupEntries[index];
                              final name = p.basename(entry.path);
                              final isDir = FileSystemEntity.isDirectorySync(entry.path);
                              final isZst = name.endsWith('.zst') || name.endsWith('.tar.zst');

                              return ListTile(
                                leading: Icon(
                                  isDir
                                      ? Icons.folder
                                      : isZst
                                          ? Icons.archive
                                          : _getFileIcon(entry.path),
                                  color: isDir
                                      ? Colors.amber
                                      : isZst
                                          ? Colors.teal
                                          : null,
                                ),
                                title: Text(name),
                                subtitle: Text(_getFileInfo(entry)),
                                onTap: isDir ? () => _navigateToDirectory(entry.path) : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isZst)
                                      IconButton(
                                        icon: const Icon(Icons.folder_zip),
                                        tooltip: 'Extract',
                                        onPressed: () => _decompressFile(entry.path),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      tooltip: 'Delete',
                                      onPressed: () => _deleteEntry(entry.path),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
