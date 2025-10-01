import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/settings.dart';

class BackupManagerPage extends StatefulWidget {
  const BackupManagerPage({super.key});

  @override
  State<BackupManagerPage> createState() => _BackupManagerPageState();
}

class _BackupManagerPageState extends State<BackupManagerPage> {
  String backupFolderPath = '';
  List<String> pathHistory = [];
  List<FileSystemEntity> backupEntries = [];
  bool loadingBackups = false;
  String error = '';

  // Extraction options
  bool extractInProgress = false;
  double extractProgress = 0.0;
  String extractStatus = '';
  
  // Sort options
  SortBy sortBy = SortBy.name;
  bool sortAscending = true;

  @override
  void initState() {
    super.initState();
    _initializeBackupDirectory();
  }

  void _initializeBackupDirectory() {
    final settings = Provider.of<Settings>(context, listen: false);
    backupFolderPath = p.join(settings.backupPath ?? settings.prefixDirectory, 'game_backups');
    _refreshBackupEntries();
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

      // Filter entries
      backupEntries = entitiesList.where((e) {
        final name = p.basename(e.path);
        return !name.startsWith('.');
      }).toList();

      _sortEntries();

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

  void _sortEntries() {
    backupEntries.sort((a, b) {
      bool aIsDir = FileSystemEntity.isDirectorySync(a.path);
      bool bIsDir = FileSystemEntity.isDirectorySync(b.path);

      // Always put directories first
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;

      int comparison;
      switch (sortBy) {
        case SortBy.name:
          comparison = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
          break;
        case SortBy.date:
          final aStat = a.statSync();
          final bStat = b.statSync();
          comparison = aStat.modified.compareTo(bStat.modified);
          break;
        case SortBy.size:
          if (aIsDir || bIsDir) {
            comparison = p.basename(a.path).compareTo(p.basename(b.path));
          } else {
            final aStat = a.statSync();
            final bStat = b.statSync();
            comparison = aStat.size.compareTo(bStat.size);
          }
          break;
      }

      return sortAscending ? comparison : -comparison;
    });
  }

  Future<void> _changeSortOrder(SortBy newSortBy) async {
    setState(() {
      if (sortBy == newSortBy) {
        sortAscending = !sortAscending;
      } else {
        sortBy = newSortBy;
        sortAscending = true;
      }
    });
    _sortEntries();
  }

  Future<void> _selectBackupFolder() async {
    final String? selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Backup Folder',
      initialDirectory: backupFolderPath,
    );

    if (selectedDir != null) {
      setState(() {
        backupFolderPath = selectedDir;
        pathHistory.clear();
      });
      await _refreshBackupEntries();
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

  Future<void> _extractFile(String filePath) async {
    final String? destinationDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Where to Extract',
      initialDirectory: p.dirname(filePath),
    );

    if (destinationDir == null) return;

    setState(() {
      extractInProgress = true;
      extractProgress = 0.0;
      extractStatus = 'Starting extraction...';
    });

    try {
      final fileName = p.basename(filePath);

      // Create command based on file type
      String cmd;
      if (fileName.endsWith('.tar.zst')) {
        cmd = 'pv -n "$filePath" | zstd -d | tar xf - -C "$destinationDir"';
      } else if (fileName.endsWith('.zst')) {
        final outFile = p.join(destinationDir, p.basenameWithoutExtension(fileName));
        cmd = 'pv -n "$filePath" | zstd -d > "$outFile"';
      } else if (fileName.endsWith('.tar.gz')) {
        cmd = 'pv -n "$filePath" | tar xzf - -C "$destinationDir"';
      } else if (fileName.endsWith('.tar.xz')) {
        cmd = 'pv -n "$filePath" | tar xJf - -C "$destinationDir"';
      } else if (fileName.endsWith('.tar')) {
        cmd = 'pv -n "$filePath" | tar xf - -C "$destinationDir"';
      } else if (fileName.endsWith('.zip')) {
        cmd = 'unzip -o "$filePath" -d "$destinationDir"';
      } else {
        throw Exception('Unsupported file format: ${p.extension(fileName)}');
      }

      setState(() {
        extractStatus = 'Extracting $fileName...';
      });

      final process = await Process.start('sh', ['-c', cmd]);

      // Listen to stderr for pv progress (if using pv)
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        try {
          final progress = double.parse(data.trim()) / 100.0;
          setState(() {
            extractProgress = progress.clamp(0.0, 1.0);
            extractStatus = 'Extracting... ${(extractProgress * 100).toStringAsFixed(1)}%';
          });
        } catch (_) {
          // If it's not progress data, might be error messages
          if (data.trim().isNotEmpty) {
            setState(() {
              extractStatus = data.trim();
            });
          }
        }
      });

      // Listen to stdout for other output
      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        if (data.trim().isNotEmpty) {
          setState(() {
            extractStatus = data.trim();
          });
        }
      });

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        throw Exception('Extraction failed with exit code $exitCode');
      }

      setState(() {
        extractProgress = 1.0;
        extractStatus = 'Extraction completed successfully!';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File extracted to $destinationDir')),
        );
      }

    } catch (e) {
      setState(() {
        error = 'Extraction error: $e';
        extractStatus = 'Extraction failed: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error extracting file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        extractInProgress = false;
      });
    }
  }

  Future<void> _deleteFile(String filePath) async {
    final fileName = p.basename(filePath);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Backup'),
        content: Text('Are you sure you want to delete "$fileName"?\n\nThis action cannot be undone.'),
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

    if (confirm == true) {
      try {
        final file = File(filePath);
        await file.delete();
        await _refreshBackupEntries();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted $fileName')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting file: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _renameFile(String filePath) async {
    final fileName = p.basename(filePath);
    final fileExtension = p.extension(fileName);
    final fileNameWithoutExt = p.basenameWithoutExtension(fileName);

    final controller = TextEditingController(text: fileNameWithoutExt);
    
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Backup'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'New name',
            suffixText: fileExtension,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != fileNameWithoutExt) {
      try {
        final file = File(filePath);
        final newPath = p.join(p.dirname(filePath), '$newName$fileExtension');
        await file.rename(newPath);
        await _refreshBackupEntries();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Renamed to $newName$fileExtension')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error renaming file: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _getFileInfo(FileSystemEntity entity) {
    try {
      final stat = entity.statSync();
      final size = stat.size;
      final modified = stat.modified;
      
      String sizeString;
      if (size < 1024) {
        sizeString = '${size}B';
      } else if (size < 1024 * 1024) {
        sizeString = '${(size / 1024).toStringAsFixed(1)}KB';
      } else if (size < 1024 * 1024 * 1024) {
        sizeString = '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
      } else {
        sizeString = '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
      }

      return '$sizeString • ${modified.toString().split('.')[0]}';
    } catch (e) {
      return 'Unknown size';
    }
  }

  IconData _getFileIcon(String path) {
    final extension = p.extension(path).toLowerCase();
    switch (extension) {
      case '.zst':
      case '.tar.zst':
      case '.tar.gz':
      case '.tar.xz':
      case '.tar':
        return Icons.archive;
      case '.zip':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup Manager'),
        actions: [
          // Sort menu
          PopupMenuButton<SortBy>(
            icon: Icon(
              sortBy == SortBy.name ? Icons.sort_by_alpha :
              sortBy == SortBy.date ? Icons.access_time :
              Icons.sort,
            ),
            tooltip: 'Sort by',
            onSelected: _changeSortOrder,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: SortBy.name,
                child: Row(
                  children: [
                    const Icon(Icons.sort_by_alpha),
                    const SizedBox(width: 8),
                    const Text('Name'),
                    if (sortBy == SortBy.name) ...[
                      const Spacer(),
                      Icon(sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: SortBy.date,
                child: Row(
                  children: [
                    const Icon(Icons.access_time),
                    const SizedBox(width: 8),
                    const Text('Date'),
                    if (sortBy == SortBy.date) ...[
                      const Spacer(),
                      Icon(sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: SortBy.size,
                child: Row(
                  children: [
                    const Icon(Icons.sort),
                    const SizedBox(width: 8),
                    const Text('Size'),
                    if (sortBy == SortBy.size) ...[
                      const Spacer(),
                      Icon(sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                    ],
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Change Backup Folder',
            onPressed: extractInProgress ? null : _selectBackupFolder,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: extractInProgress ? null : _refreshBackupEntries,
          ),
        ],
      ),
      body: Column(
        children: [
          // Navigation bar
          Container(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Parent Directory',
                  onPressed: extractInProgress ? null : _navigateUp,
                ),
                if (pathHistory.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Go Back',
                    onPressed: extractInProgress ? null : _navigateBack,
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

          const Divider(height: 1),

          // Error display
          if (error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.withValues(alpha:0.1),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.red),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => error = ''),
                  ),
                ],
              ),
            ),

          // Progress indicator for extraction
          if (extractInProgress)
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    extractStatus,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: extractProgress > 0 ? extractProgress : null,
                  ),
                ],
              ),
            ),

          // File listing
          Expanded(
            child: extractInProgress && backupEntries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Processing...',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  )
                : loadingBackups
                    ? const Center(child: CircularProgressIndicator())
                    : backupEntries.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.folder_open,
                                  size: 64,
                                  color: theme.colorScheme.onSurface.withValues(alpha:0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No backups found',
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha:0.5),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Create backups from the Files tab or change the backup folder',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha:0.7),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: backupEntries.length,
                            itemBuilder: (context, index) {
                              final entry = backupEntries[index];
                              final name = p.basename(entry.path);
                              final isDir = FileSystemEntity.isDirectorySync(entry.path);
                              final isArchive = !isDir && (name.endsWith('.zst') || 
                                                          name.endsWith('.tar.zst') || 
                                                          name.endsWith('.tar.gz') || 
                                                          name.endsWith('.tar.xz') || 
                                                          name.endsWith('.tar') ||
                                                          name.endsWith('.zip'));

                              return ListTile(
                                leading: Icon(
                                  isDir
                                      ? Icons.folder
                                      : _getFileIcon(entry.path),
                                  color: isDir
                                      ? Colors.amber
                                      : isArchive
                                          ? Colors.teal
                                          : null,
                                ),
                                title: Text(name),
                                subtitle: Text(_getFileInfo(entry)),
                                onTap: isDir 
                                    ? () => _navigateToDirectory(entry.path) 
                                    : null,
                                trailing: isDir ? null : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isArchive)
                                      IconButton(
                                        icon: const Icon(Icons.unarchive),
                                        tooltip: 'Extract',
                                        onPressed: extractInProgress 
                                            ? null 
                                            : () => _extractFile(entry.path),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      tooltip: 'Rename',
                                      onPressed: extractInProgress 
                                          ? null 
                                          : () => _renameFile(entry.path),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      tooltip: 'Delete',
                                      onPressed: extractInProgress 
                                          ? null 
                                          : () => _deleteFile(entry.path),
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

enum SortBy {
  name,
  date,
  size,
} 