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
  return name
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .replaceAll(RegExp(r'\s+'), '_');
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
    backupFolderPath =
        p.join(settings.backupPath ?? settings.prefixDirectory, 'game_backups');

    setState(() => loading = false);
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
              final savePath = p.join(
                  userDir.path, parts[1].substring(1)); // Remove leading /
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
    // Default to home directory or current source folder
    String initialDir = sourceFolderPath.isNotEmpty
        ? sourceFolderPath
        : selectedGame != null
            ? p.dirname(selectedGame!.exe.path)
            : '/home';

    final String? selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Folder to Backup',
      initialDirectory: initialDir,
    );

    if (selectedDir != null) {
      setState(() {
        sourceFolderPath = selectedDir;
        // Clear save data paths when manually selecting a new folder
        // unless we have a selected game that we can use for auto-discovery
        if (selectedGame == null) {
          saveDataPaths.clear();
        }
      });
    }
  }

  Future<void> _addSaveDataFolder() async {
    // Default to Documents folder if we have a selected game, otherwise home
    String initialDir = '/home';

    if (selectedGame != null) {
      final prefix = selectedGame!.prefix;
      String prefixInitialDir = p.join(prefix.path, 'drive_c/users');

      // Try to find the first user directory
      try {
        final usersDir = Directory(prefixInitialDir);
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
    }

    final String? selectedDir = await FilePicker.platform.getDirectoryPath(
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
      List<String> excludes = [
        '--exclude=*.lock',
        '--exclude=*/tmp/*',
        '--exclude=*/cache/*'
      ];

      if (!includeGameSaves) {
        excludes.addAll(['--exclude=*/saves/*', '--exclude=*/Saves/*']);
      }

      if (!includeConfigs) {
        excludes.addAll(
            ['--exclude=*/config/*', '--exclude=*.ini', '--exclude=*.cfg']);
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
            final estimatedProgress =
                (currentSize * 3) / totalFileSize; // Assume 3:1 compression
            setState(() {
              backupProgress = estimatedProgress.clamp(
                  0.0, 0.95); // Don't show 100% until done
              backupStatus =
                  'Creating backup... ${(backupProgress * 100).toStringAsFixed(1)}%';
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
        cmd =
            'pv -n "$filePath" | zstd -d --threads=$compressionThreads | tar xf - -C "$destinationDir"';
      } else if (fileName.endsWith('.zst')) {
        final outFile =
            p.join(destinationDir, p.basenameWithoutExtension(fileName));
        cmd =
            'pv -n "$filePath" | zstd -d --threads=$compressionThreads > "$outFile"';
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Create Backup${selectedGame != null ? ' - ${selectedGame!.exe.name}' : ''}'),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        actions: [
          if (availableGames.isNotEmpty)
            PopupMenuButton<GameEntry>(
              tooltip: 'Quick Select from Registered Games',
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
                return [
                  const PopupMenuItem<GameEntry>(
                    enabled: false,
                    child: Text(
                      'Select a registered game:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ...availableGames.map((game) {
                    return PopupMenuItem<GameEntry>(
                      value: game,
                      child: Row(
                        children: [
                          const Icon(Icons.videogame_asset, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(game.exe.name)),
                        ],
                      ),
                    );
                  }).toList(),
                ];
              },
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
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main instruction
                Text(
                  'Select a folder to backup:',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Optional game selection for convenience
                if (availableGames.isNotEmpty) ...[
                  Row(
                    children: [
                      Text(
                        'Quick select from games: ',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (selectedGame != null)
                        Chip(
                          label: Text(selectedGame!.exe.name),
                          onDeleted: () {
                            setState(() {
                              selectedGame = null;
                              saveDataPaths.clear();
                            });
                          },
                          deleteIcon: const Icon(Icons.clear, size: 18),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Source folder selection - now the primary action
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Folder to backup:',
                              style: theme.textTheme.bodySmall,
                            ),
                            Text(
                              sourceFolderPath.isEmpty
                                  ? 'Click "Browse" to select a folder'
                                  : sourceFolderPath,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: sourceFolderPath.isEmpty
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                                fontStyle: sourceFolderPath.isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Save data folders section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Additional Save Data Folders:',
                      style: theme.textTheme.titleSmall,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add Folder'),
                      onPressed: backupInProgress ? null : _addSaveDataFolder,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
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
                      color: theme.colorScheme.surface.withOpacity(0.5),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.6)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Optional: Add additional folders (like save files) to include in the backup.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontStyle: FontStyle.italic),
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
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            path,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 18),
                            onPressed: backupInProgress
                                ? null
                                : () => _removeSaveDataFolder(path),
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
                        onChanged: backupInProgress
                            ? null
                            : (value) {
                                // Disable during backup
                                setState(() {
                                  compressionLevel = value.round();
                                });
                              },
                      ),
                    ),
                    Text(
                      "$compressionLevel",
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
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
                        label: compressionThreads == 0
                            ? "Auto"
                            : compressionThreads.toString(),
                        onChanged: backupInProgress
                            ? null
                            : (value) {
                                // Disable during backup
                                setState(() {
                                  compressionThreads = value.round();
                                });
                              },
                      ),
                    ),
                    Text(
                      compressionThreads == 0 ? "Auto" : "$compressionThreads",
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
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
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic),
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
                        onChanged: backupInProgress
                            ? null
                            : (value) {
                                // Disable during backup
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
                        onChanged: backupInProgress
                            ? null
                            : (value) {
                                // Disable during backup
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    onPressed: sourceFolderPath.isEmpty || backupInProgress
                        ? null
                        : _createBackup,
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

          // Error display
          if (error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.withOpacity(0.1),
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
        ],
      ),
    );
  }
}
