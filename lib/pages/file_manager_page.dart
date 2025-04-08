import 'dart:io';
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
    final settings = Provider.of<Settings>(context, listen: false);

    // Initialize source folder path if a game is selected
    if (selectedGame != null) {
      setState(() {
        sourceFolderPath = p.dirname(selectedGame!.exe.path);
      });
    }

    // Initialize backup folder path from settings or default
    final baseDir = settings.backupPath?.isNotEmpty == true
        ? settings.backupPath!
        : p.join(settings.prefixDirectory, 'backups');

    setState(() {
      backupFolderPath = baseDir;
      loading = false;
    });

    _refreshBackupEntries();
  }

  Future<void> _selectSourceFolder() async {
    if (selectedGame == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a game first')),
      );
      return;
    }

    // Default to the parent directory of the game executable
    String initialDir = p.dirname(selectedGame!.exe.path);

    final String? selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Folder to Backup',
      initialDirectory: initialDir,
    );

    if (selectedDir != null) {
      setState(() {
        sourceFolderPath = selectedDir;
      });
    }
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
        const SnackBar(content: Text('Please select a source folder first')),
      );
      return;
    }

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
    });

    try {
      // Build exclude list
      List<String> excludes = ['--exclude=*.lock', '--exclude=*/tmp/*'];

      if (!includeGameSaves) {
        excludes.addAll(['--exclude=*/saves/*', '--exclude=*/Saves/*']);
      }

      if (!includeConfigs) {
        excludes.addAll(['--exclude=*/config/*', '--exclude=*.ini', '--exclude=*.cfg']);
      }

      // Create progress monitor using a pipe
      final process = await Process.start('sh', [
        '-c',
        'tar cf - -C "${p.dirname(sourceFolderPath)}" "${p.basename(sourceFolderPath)}" ${excludes.join(' ')} | pv -n | zstd -$compressionLevel --threads=$compressionThreads -o "$outputPath"'
      ]);

      // Listen to stderr for pv progress
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        // Try to parse progress percentage
        try {
          final progress = double.parse(data.trim()) / 100.0;
          setState(() {
            backupProgress = progress.clamp(0.0, 1.0);
          });
        } catch (_) {}
      });

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        throw Exception('Backup process failed with exit code $exitCode');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup created: $backupName')),
      );

      await _refreshBackupEntries();
    } catch (e) {
      setState(() {
        error = 'Backup error: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating backup: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
              onSelected: (game) {
                setState(() {
                  selectedGame = game;
                  sourceFolderPath = p.dirname(game.exe.path);
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
            onPressed: _refreshBackupEntries,
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
                      onPressed: _selectSourceFolder,
                    ),
                  ],
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
                        onChanged: (value) {
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
                        onChanged: (value) {
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
                        onChanged: (value) {
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
                        onChanged: (value) {
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
                        'Creating backup... ${(backupProgress * 100).toStringAsFixed(1)}%',
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
                  onPressed: _navigateUp,
                ),
                if (pathHistory.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Go Back',
                    onPressed: _navigateBack,
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

          // Bottom half - Backup files listing
          Expanded(
            child: loadingBackups
                ? const Center(child: CircularProgressIndicator())
                : backupEntries.isEmpty
                    ? Center(
                        child: const Text('No backups found'),
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
