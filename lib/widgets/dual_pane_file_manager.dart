import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../services/file_operations_service.dart';
import '../services/backup_service.dart';
import '../services/archive_service.dart';

enum FileManagerAction {
  copy,
  move,
  delete,
  rename,
  createFolder,
  addToGameLibrary,
  openWith,
  properties
}

enum SortBy { name, size, modified, type }

class FileItem {
  final FileSystemEntity entity;
  final bool isDirectory;
  final String name;
  final int size;
  final DateTime modified;
  final String type;
  final bool isGameExecutable;
  final bool isInGameLibrary;

  FileItem({
    required this.entity,
    required this.isDirectory,
    required this.name,
    required this.size,
    required this.modified,
    required this.type,
    this.isGameExecutable = false,
    this.isInGameLibrary = false,
  });
}

class DualPaneFileManager extends StatefulWidget {
  final String? initialLeftPath;
  final String? initialRightPath;
  final List<GameEntry>? gameEntries;
  final Function(String exePath)? onAddToGameLibrary;
  final Function(String oldPath, String newPath)? onUpdateGamePath;

  const DualPaneFileManager({
    super.key,
    this.initialLeftPath,
    this.initialRightPath,
    this.gameEntries,
    this.onAddToGameLibrary,
    this.onUpdateGamePath,
  });

  @override
  State<DualPaneFileManager> createState() => _DualPaneFileManagerState();
}

class _DualPaneFileManagerState extends State<DualPaneFileManager> {
  // Pane states
  String leftPath = '';
  String rightPath = '';
  List<FileItem> leftFiles = [];
  List<FileItem> rightFiles = [];
  List<String> leftHistory = [];
  List<String> rightHistory = [];
  int leftHistoryIndex = -1;
  int rightHistoryIndex = -1;
  
  // Selection and UI state
  Set<String> leftSelectedFiles = {};
  Set<String> rightSelectedFiles = {};
  bool leftLoading = false;
  bool rightLoading = false;
  String leftError = '';
  String rightError = '';
  PaneType activePaneType = PaneType.left;
  
  // Sorting
  SortBy leftSortBy = SortBy.name;
  SortBy rightSortBy = SortBy.name;
  bool leftSortAscending = true;
  bool rightSortAscending = true;
  
  // File operations
  bool operationInProgress = false;
  double operationProgress = 0.0;
  String operationStatus = '';
  
  // Game library integration
  List<GameEntry> gameEntries = [];
  Set<String> gameExecutablePaths = {};
  
  // Favorite paths
  List<String> favoritePaths = [];

  @override
  void initState() {
    super.initState();
    _initializeManager();
  }

  void _initializeManager() {
    // Initialize favorite paths with common locations
    _initializeFavoritePaths();
    
    // Set default paths - Downloads folder for both sides
    final downloadsPath = p.join(Platform.environment['HOME'] ?? '/', 'Downloads');
    leftPath = widget.initialLeftPath ?? downloadsPath;
    rightPath = widget.initialRightPath ?? downloadsPath;
    
    gameEntries = widget.gameEntries ?? [];
    _updateGameExecutablePaths();
    
    _refreshPane(PaneType.left);
    _refreshPane(PaneType.right);
  }
  
  void _initializeFavoritePaths() {
    final homeDir = Platform.environment['HOME'] ?? '/';
    favoritePaths = [
      p.join(homeDir, 'Downloads'),
      p.join(homeDir, 'Documents'),
      p.join(homeDir, 'Desktop'),
      homeDir,
      '/',
    ];
    
    // Add settings-based paths if available
    try {
      final settings = Provider.of<Settings>(context, listen: false);
      if (settings.prefixDirectory.isNotEmpty && !favoritePaths.contains(settings.prefixDirectory)) {
        favoritePaths.add(settings.prefixDirectory);
      }
      if (settings.backupPath != null && settings.backupPath!.isNotEmpty && !favoritePaths.contains(settings.backupPath!)) {
        favoritePaths.add(settings.backupPath!);
      }
    } catch (e) {
      // Settings not available during initialization
    }
  }

  void _updateGameExecutablePaths() {
    gameExecutablePaths.clear();
    for (final game in gameEntries) {
      gameExecutablePaths.add(game.exe.path);
    }
  }

  Future<void> _refreshPane(PaneType pane) async {
    final path = pane == PaneType.left ? leftPath : rightPath;
    if (path.isEmpty) return;

    setState(() {
      if (pane == PaneType.left) {
        leftLoading = true;
        leftError = '';
      } else {
        rightLoading = true;
        rightError = '';
      }
    });

    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        throw FileSystemException('Directory does not exist: $path');
      }

      final entities = await directory.list().toList();
      final files = <FileItem>[];

      for (final entity in entities) {
        final stat = await entity.stat();
        final isDir = entity is Directory;
        final name = p.basename(entity.path);
        final isExe = !isDir && _isExecutableFile(entity.path);
        final isInLibrary = gameExecutablePaths.contains(entity.path);

        files.add(FileItem(
          entity: entity,
          isDirectory: isDir,
          name: name,
          size: isDir ? 0 : stat.size,
          modified: stat.modified,
          type: isDir ? 'Folder' : _getFileType(entity.path),
          isGameExecutable: isExe,
          isInGameLibrary: isInLibrary,
        ));
      }

      // Sort files
      final sortBy = pane == PaneType.left ? leftSortBy : rightSortBy;
      final ascending = pane == PaneType.left ? leftSortAscending : rightSortAscending;
      _sortFiles(files, sortBy, ascending);

      setState(() {
        if (pane == PaneType.left) {
          leftFiles = files;
          leftLoading = false;
        } else {
          rightFiles = files;
          rightLoading = false;
        }
      });
    } catch (e) {
      setState(() {
        if (pane == PaneType.left) {
          leftError = e.toString();
          leftLoading = false;
        } else {
          rightError = e.toString();
          rightLoading = false;
        }
      });
    }
  }

  void _sortFiles(List<FileItem> files, SortBy sortBy, bool ascending) {
    files.sort((a, b) {
      // Always show directories first
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;

      int compare;
      switch (sortBy) {
        case SortBy.name:
          compare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case SortBy.size:
          compare = a.size.compareTo(b.size);
          break;
        case SortBy.modified:
          compare = a.modified.compareTo(b.modified);
          break;
        case SortBy.type:
          compare = a.type.compareTo(b.type);
          break;
      }
      return ascending ? compare : -compare;
    });
  }

  bool _isExecutableFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.exe' || ext == '.msi' || ext == '.bat' || ext == '.cmd';
  }

  String _getFileType(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.exe':
        return 'Executable';
      case '.msi':
        return 'Installer';
      case '.dll':
        return 'Library';
      case '.bat':
      case '.cmd':
        return 'Batch Script';
      case '.txt':
        return 'Text File';
      case '.zip':
      case '.rar':
      case '.7z':
        return 'Archive';
      case '.jpg':
      case '.png':
      case '.bmp':
        return 'Image';
      default:
        return ext.isEmpty ? 'File' : ext.substring(1).toUpperCase();
    }
  }

  void _navigateToPath(PaneType pane, String newPath) {
    if (pane == PaneType.left) {
      _addToHistory(PaneType.left, leftPath);
      leftPath = newPath;
      leftSelectedFiles.clear();
    } else {
      _addToHistory(PaneType.right, rightPath);
      rightPath = newPath;
      rightSelectedFiles.clear();
    }
    _refreshPane(pane);
  }

  void _addToHistory(PaneType pane, String path) {
    if (pane == PaneType.left) {
      leftHistory = leftHistory.take(leftHistoryIndex + 1).toList();
      leftHistory.add(path);
      leftHistoryIndex = leftHistory.length - 1;
    } else {
      rightHistory = rightHistory.take(rightHistoryIndex + 1).toList();
      rightHistory.add(path);
      rightHistoryIndex = rightHistory.length - 1;
    }
  }

  void _goBack(PaneType pane) {
    if (pane == PaneType.left && leftHistoryIndex > 0) {
      leftHistoryIndex--;
      leftPath = leftHistory[leftHistoryIndex];
      _refreshPane(PaneType.left);
    } else if (pane == PaneType.right && rightHistoryIndex > 0) {
      rightHistoryIndex--;
      rightPath = rightHistory[rightHistoryIndex];
      _refreshPane(PaneType.right);
    }
  }

  void _goForward(PaneType pane) {
    if (pane == PaneType.left && leftHistoryIndex < leftHistory.length - 1) {
      leftHistoryIndex++;
      leftPath = leftHistory[leftHistoryIndex];
      _refreshPane(PaneType.left);
    } else if (pane == PaneType.right && rightHistoryIndex < rightHistory.length - 1) {
      rightHistoryIndex++;
      rightPath = rightHistory[rightHistoryIndex];
      _refreshPane(PaneType.right);
    }
  }

  void _goUp(PaneType pane) {
    final currentPath = pane == PaneType.left ? leftPath : rightPath;
    final parentPath = p.dirname(currentPath);
    if (parentPath != currentPath) {
      _navigateToPath(pane, parentPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dual Pane File Manager'),
        backgroundColor: Colors.blueGrey[800],
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.star_border),
            tooltip: 'Manage Favorites',
            onPressed: _showManageFavoritesDialog,
          ),
          const VerticalDivider(),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'Create New Folder',
            onPressed: _showCreateFolderDialog,
          ),
          IconButton(
            icon: const Icon(Icons.file_copy),
            tooltip: 'Quick Copy Selected',
            onPressed: _hasSelectedFiles() ? _copySelectedFiles : null,
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move),
            tooltip: 'Quick Move Selected',
            onPressed: _hasSelectedFiles() ? _moveSelectedFiles : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Quick Delete Selected',
            onPressed: _hasSelectedFiles() ? _deleteSelectedFiles : null,
          ),
          const VerticalDivider(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Both Panes',
            onPressed: _refreshBothPanes,
          ),
        ],
      ),
      body: Column(
        children: [
          // Operation progress bar
          if (operationInProgress)
            LinearProgressIndicator(
              value: operationProgress,
              backgroundColor: Colors.blueGrey[100],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blueGrey[600]!),
            ),
          if (operationInProgress)
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.blueGrey[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    operationStatus,
                    style: TextStyle(
                      color: Colors.blueGrey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          // Main dual pane content
          Expanded(
            child: Row(
              children: [
                // Left Pane
                Expanded(
                  child: _buildPane(
                    PaneType.left,
                    leftPath,
                    leftFiles,
                    leftSelectedFiles,
                    leftLoading,
                    leftError,
                    leftSortBy,
                    leftSortAscending,
                  ),
                ),
                // Divider
                Container(
                  width: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.blueGrey[200]!, Colors.blueGrey[400]!, Colors.blueGrey[200]!],
                    ),
                  ),
                ),
                // Right Pane
                Expanded(
                  child: _buildPane(
                    PaneType.right,
                    rightPath,
                    rightFiles,
                    rightSelectedFiles,
                    rightLoading,
                    rightError,
                    rightSortBy,
                    rightSortAscending,
                  ),
                ),
              ],
            ),
          ),
          // Action buttons row
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildPane(
    PaneType pane,
    String path,
    List<FileItem> files,
    Set<String> selectedFiles,
    bool loading,
    String error,
    SortBy sortBy,
    bool sortAscending,
  ) {
    return GestureDetector(
      onTap: () => setState(() => activePaneType = pane),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: activePaneType == pane ? Colors.blue : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            // Pane header with navigation
            _buildPaneHeader(pane, path),
            // Sort header
            _buildSortHeader(pane, sortBy, sortAscending),
            // File list
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : error.isNotEmpty
                      ? Center(child: Text('Error: $error'))
                      : _buildFileList(pane, files, selectedFiles),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaneHeader(PaneType pane, String path) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: activePaneType == pane ? Colors.blue[600] : Colors.blueGrey[700],
        border: Border(
          bottom: BorderSide(color: Colors.blueGrey[300]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => _goBack(pane),
            tooltip: 'Back',
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward, color: Colors.white),
            onPressed: () => _goForward(pane),
            tooltip: 'Forward',
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward, color: Colors.white),
            onPressed: () => _goUp(pane),
            tooltip: 'Up',
          ),
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => _navigateToPath(pane, Platform.environment['HOME'] ?? '/'),
            tooltip: 'Home',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.star, color: Colors.white),
            tooltip: 'Favorite Paths',
            onSelected: (path) => _navigateToPath(pane, path),
            itemBuilder: (context) => [
              const PopupMenuItem(
                enabled: false,
                child: Text(
                  'Favorites',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ...favoritePaths.map((favPath) {
                final displayName = _getFavoriteDisplayName(favPath);
                return PopupMenuItem(
                  value: favPath,
                  child: Row(
                    children: [
                      Icon(_getFavoriteIcon(favPath), size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(displayName)),
                    ],
                  ),
                );
              }),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'add_current',
                child: Row(
                  children: [
                    const Icon(Icons.add, size: 16),
                    const SizedBox(width: 8),
                    const Text('Add Current Path'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              path,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.select_all),
            onPressed: () => _selectAll(pane),
            tooltip: 'Select All (Ctrl+A)',
          ),
          IconButton(
            icon: const Icon(Icons.deselect),
            onPressed: () => _clearSelection(pane),
            tooltip: 'Clear Selection',
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _showPathEditor(pane, path),
            tooltip: 'Edit Path',
          ),
        ],
      ),
    );
  }

  Widget _buildSortHeader(PaneType pane, SortBy sortBy, bool sortAscending) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: Colors.blueGrey[100],
        border: Border(
          bottom: BorderSide(color: Colors.blueGrey[300]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          _buildSortButton('Name', SortBy.name, pane, sortBy, sortAscending),
          const SizedBox(width: 8),
          _buildSortButton('Size', SortBy.size, pane, sortBy, sortAscending),
          const SizedBox(width: 8),
          _buildSortButton('Modified', SortBy.modified, pane, sortBy, sortAscending),
          const SizedBox(width: 8),
          _buildSortButton('Type', SortBy.type, pane, sortBy, sortAscending),
        ],
      ),
    );
  }

  Widget _buildSortButton(String label, SortBy sort, PaneType pane, SortBy currentSort, bool ascending) {
    final isSelected = currentSort == sort;
    return GestureDetector(
      onTap: () => _setSortBy(pane, sort),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.blue[700] : Colors.blueGrey[800],
              fontSize: 13,
            ),
          ),
          if (isSelected)
            Icon(
              ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: Colors.blue,
            ),
        ],
      ),
    );
  }

  Widget _buildFileList(PaneType pane, List<FileItem> files, Set<String> selectedFiles) {
    if (files.isEmpty) {
      return const Center(child: Text('No files'));
    }

    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isSelected = selectedFiles.contains(file.entity.path);
        
        return ListTile(
          selected: isSelected,
          leading: _buildFileIcon(file),
          title: Row(
            children: [
              Expanded(child: Text(file.name)),
              if (file.isInGameLibrary)
                const Icon(Icons.videogame_asset, color: Colors.green, size: 16),
              if (file.isGameExecutable && !file.isInGameLibrary)
                const Icon(Icons.add_to_photos, color: Colors.orange, size: 16),
            ],
          ),
          subtitle: file.isDirectory ? null : Text(_formatFileInfo(file)),
          onTap: () => _handleFileTap(pane, file, selectedFiles),
          onLongPress: () => _showContextMenu(pane, file),
          trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
        );
      },
    );
  }
  


  Widget _buildFileIcon(FileItem file) {
    if (file.isDirectory) {
      return const Icon(Icons.folder, color: Colors.blue);
    }
    
    if (file.isGameExecutable) {
      return Icon(
        Icons.sports_esports,
        color: file.isInGameLibrary ? Colors.green : Colors.orange,
      );
    }

    switch (file.type) {
      case 'Executable':
        return const Icon(Icons.launch, color: Colors.red);
      case 'Installer':
        return const Icon(Icons.install_desktop, color: Colors.purple);
      case 'Archive':
        return const Icon(Icons.archive, color: Colors.brown);
      case 'Image':
        return const Icon(Icons.image, color: Colors.green);
      case 'Text File':
        return const Icon(Icons.description, color: Colors.blue);
      default:
        return const Icon(Icons.insert_drive_file, color: Colors.grey);
    }
  }

  String _formatFileInfo(FileItem file) {
    final size = _formatFileSize(file.size);
    final date = '${file.modified.day}/${file.modified.month}/${file.modified.year}';
    return '$size • $date • ${file.type}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _handleFileTap(PaneType pane, FileItem file, Set<String> selectedFiles) {
    if (file.isDirectory) {
      _navigateToPath(pane, file.entity.path);
    } else {
      setState(() {
        if (selectedFiles.contains(file.entity.path)) {
          selectedFiles.remove(file.entity.path);
        } else {
          selectedFiles.add(file.entity.path);
        }
      });
    }
  }

  Widget _buildActionButtons() {
    final hasSelection = _hasSelectedFiles();
    final selectedCount = (activePaneType == PaneType.left ? leftSelectedFiles : rightSelectedFiles).length;
    
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        border: Border(
          top: BorderSide(color: Colors.blueGrey[200]!, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasSelection)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                '$selectedCount item${selectedCount == 1 ? '' : 's'} selected in ${activePaneType == PaneType.left ? 'left' : 'right'} pane',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[800],
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Tooltip(
                message: 'Copy files to opposite pane (Ctrl+C)',
                child: ElevatedButton.icon(
                  onPressed: hasSelection ? _copySelectedFiles : null,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
              ),
              Tooltip(
                message: 'Move files to opposite pane (Ctrl+X)',
                child: ElevatedButton.icon(
                  onPressed: hasSelection ? _moveSelectedFiles : null,
                  icon: const Icon(Icons.drive_file_move),
                  label: const Text('Move'),
                ),
              ),
              Tooltip(
                message: 'Delete selected files (Delete)',
                child: ElevatedButton.icon(
                  onPressed: hasSelection ? _deleteSelectedFiles : null,
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: hasSelection ? Colors.red : null,
                  ),
                ),
              ),
              Tooltip(
                message: 'Add selected executables to game library',
                child: ElevatedButton.icon(
                  onPressed: _hasSelectedExecutables() ? _addSelectedToGameLibrary : null,
                  icon: const Icon(Icons.videogame_asset),
                  label: const Text('Add to Library'),
                ),
              ),
              Tooltip(
                message: 'Backup selected files/folders with zstd compression',
                child: ElevatedButton.icon(
                  onPressed: hasSelection ? _backupSelectedFiles : null,
                  icon: const Icon(Icons.backup),
                  label: const Text('Backup'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              Tooltip(
                message: 'Extract selected archives',
                child: ElevatedButton.icon(
                  onPressed: _hasSelectedArchives() ? _extractSelectedArchives : null,
                  icon: const Icon(Icons.unarchive),
                  label: const Text('Extract'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              Tooltip(
                message: 'Create archive from selected files',
                child: ElevatedButton.icon(
                  onPressed: hasSelection ? _createArchiveFromSelected : null,
                  icon: const Icon(Icons.archive),
                  label: const Text('Archive'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (hasSelection)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => _selectAll(activePaneType),
                    icon: Icon(Icons.select_all, size: 16, color: Colors.blueGrey[700]),
                    label: Text('Select All', style: TextStyle(color: Colors.blueGrey[700])),
                  ),
                  const SizedBox(width: 16),
                  TextButton.icon(
                    onPressed: () => _clearSelection(activePaneType),
                    icon: Icon(Icons.deselect, size: 16, color: Colors.blueGrey[700]),
                    label: Text('Clear Selection', style: TextStyle(color: Colors.blueGrey[700])),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Action methods (stubs for now - will implement full functionality)
  bool _hasSelectedFiles() {
    return leftSelectedFiles.isNotEmpty || rightSelectedFiles.isNotEmpty;
  }

  bool _hasSelectedExecutables() {
    final allSelected = [...leftSelectedFiles, ...rightSelectedFiles];
    return allSelected.any((path) => _isExecutableFile(path));
  }

  void _setSortBy(PaneType pane, SortBy sortBy) {
    setState(() {
      if (pane == PaneType.left) {
        if (leftSortBy == sortBy) {
          leftSortAscending = !leftSortAscending;
        } else {
          leftSortBy = sortBy;
          leftSortAscending = true;
        }
      } else {
        if (rightSortBy == sortBy) {
          rightSortAscending = !rightSortAscending;
        } else {
          rightSortBy = sortBy;
          rightSortAscending = true;
        }
      }
    });
    _refreshPane(pane);
  }

  void _refreshBothPanes() {
    _refreshPane(PaneType.left);
    _refreshPane(PaneType.right);
  }
  
  void _selectAll(PaneType pane) {
    final files = pane == PaneType.left ? leftFiles : rightFiles;
    final selectedFiles = pane == PaneType.left ? leftSelectedFiles : rightSelectedFiles;
    
    setState(() {
      selectedFiles.clear();
      selectedFiles.addAll(files.map((f) => f.entity.path));
    });
  }
  
  void _clearSelection(PaneType pane) {
    setState(() {
      if (pane == PaneType.left) {
        leftSelectedFiles.clear();
      } else {
        rightSelectedFiles.clear();
      }
    });
  }

  // Placeholder methods for actions
  void _copySelectedFiles() async {
    final sourceFiles = activePaneType == PaneType.left ? leftSelectedFiles : rightSelectedFiles;
    final destinationPath = activePaneType == PaneType.left ? rightPath : leftPath;
    
    if (sourceFiles.isEmpty) return;
    
    setState(() {
      operationInProgress = true;
      operationProgress = 0.0;
      operationStatus = 'Preparing to copy files...';
    });
    
    try {
      final result = await FileOperationsService.copyFiles(
        sourceFiles.toList(),
        destinationPath,
        (progress, currentFile) {
          setState(() {
            operationProgress = progress;
            operationStatus = 'Copying: ${p.basename(currentFile)}';
          });
        },
      );
      
      setState(() {
        operationInProgress = false;
        if (activePaneType == PaneType.left) {
          leftSelectedFiles.clear();
        } else {
          rightSelectedFiles.clear();
        }
      });
      
      // Refresh destination pane
      _refreshPane(activePaneType == PaneType.left ? PaneType.right : PaneType.left);
      
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully copied ${result.processedFiles.length} files')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copy failed: ${result.error}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      setState(() {
        operationInProgress = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copy error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _backupSelectedFiles() async {
    final sourceFiles = activePaneType == PaneType.left ? leftSelectedFiles : rightSelectedFiles;
    
    if (sourceFiles.isEmpty) return;
    
    // Show backup dialog to choose backup directory and name
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _BackupDialog(
        selectedFiles: sourceFiles.toList(),
      ),
    );
    
    if (result == null) return;
    
    final backupDir = result['backupDir']!;
    final backupName = result['backupName']!;
    
    setState(() {
      operationInProgress = true;
      operationProgress = 0.0;
      operationStatus = 'Preparing backup...';
    });
    
    try {
      final backupResult = await BackupService.createBackup(
        sourcePaths: sourceFiles.toList(),
        backupDir: backupDir,
        backupName: backupName,
        onProgress: (progress) {
          setState(() {
            operationProgress = progress;
          });
        },
        onStatus: (status) {
          setState(() {
            operationStatus = status;
          });
        },
      );
      
      setState(() {
        operationInProgress = false;
        if (activePaneType == PaneType.left) {
          leftSelectedFiles.clear();
        } else {
          rightSelectedFiles.clear();
        }
      });
      
      if (backupResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup created successfully: ${p.basename(backupResult.backupPath!)}'),
            backgroundColor: Colors.green,
          ),
        );
        // Show option to open backup location
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup saved to: ${backupResult.backupPath!}'),
            action: SnackBarAction(
              label: 'Open Location',
              onPressed: () {
                _navigateToPath(activePaneType == PaneType.left ? PaneType.right : PaneType.left, p.dirname(backupResult.backupPath!));
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: ${backupResult.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        operationInProgress = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _hasSelectedArchives() {
    final sourceFiles = activePaneType == PaneType.left ? leftSelectedFiles : rightSelectedFiles;
    return sourceFiles.any((filePath) => ArchiveService.isArchiveFile(filePath));
  }

  void _extractSelectedArchives() async {
    final sourceFiles = activePaneType == PaneType.left ? leftSelectedFiles : rightSelectedFiles;
    final archives = sourceFiles.where((filePath) => ArchiveService.isArchiveFile(filePath)).toList();
    
    if (archives.isEmpty) return;

    // Get destination directory (opposite pane or user choice)
    final destinationPath = activePaneType == PaneType.left ? rightPath : leftPath;
    
    // Show extraction dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.unarchive, color: Colors.green),
            SizedBox(width: 8),
            Text('Extract Archives'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Extract ${archives.length} archive${archives.length == 1 ? '' : 's'} to:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Text(
                destinationPath,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            ...archives.take(3).map((archive) => 
              Text('• ${p.basename(archive)}', style: const TextStyle(fontSize: 12))
            ),
            if (archives.length > 3)
              Text('... and ${archives.length - 3} more', 
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.unarchive),
            label: const Text('Extract'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      operationInProgress = true;
      operationProgress = 0.0;
      operationStatus = 'Preparing extraction...';
    });

    try {
      int completed = 0;
      int totalArchives = archives.length;
      List<String> extractedPaths = [];

      for (final archivePath in archives) {
        final result = await ArchiveService.extractArchive(
          archivePath: archivePath,
          extractToDir: destinationPath,
          onProgress: (progress) {
            setState(() {
              operationProgress = (completed + progress) / totalArchives;
            });
          },
          onStatus: (status) {
            setState(() {
              operationStatus = '${p.basename(archivePath)}: $status';
            });
          },
        );

        if (result.success && result.outputPath != null) {
          extractedPaths.add(result.outputPath!);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to extract ${p.basename(archivePath)}: ${result.error}'),
              backgroundColor: Colors.red,
            ),
          );
        }

        completed++;
      }

      setState(() {
        operationInProgress = false;
        if (activePaneType == PaneType.left) {
          leftSelectedFiles.clear();
        } else {
          rightSelectedFiles.clear();
        }
      });

      // Refresh destination pane
      _refreshPane(activePaneType == PaneType.left ? PaneType.right : PaneType.left);

      if (extractedPaths.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully extracted ${extractedPaths.length} archive${extractedPaths.length == 1 ? '' : 's'}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        operationInProgress = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Extraction error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _createArchiveFromSelected() async {
    final sourceFiles = activePaneType == PaneType.left ? leftSelectedFiles : rightSelectedFiles;
    
    if (sourceFiles.isEmpty) return;
    
    // Show archive creation dialog
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _ArchiveCreationDialog(
        selectedFiles: sourceFiles.toList(),
      ),
    );
    
    if (result == null) return;
    
    final outputPath = result['outputPath']!;
    final archiveType = result['archiveType']!;
    
    setState(() {
      operationInProgress = true;
      operationProgress = 0.0;
      operationStatus = 'Creating ${archiveType.toUpperCase()} archive...';
    });
    
    try {
      ArchiveResult archiveResult;
      
      switch (archiveType) {
        case 'zip':
          archiveResult = await ArchiveService.createZip(
            sourcePaths: sourceFiles.toList(),
            outputPath: outputPath,
            onProgress: (progress) {
              setState(() {
                operationProgress = progress;
              });
            },
            onStatus: (status) {
              setState(() {
                operationStatus = status;
              });
            },
          );
          break;
        case 'rar':
          archiveResult = await ArchiveService.createRar(
            sourcePaths: sourceFiles.toList(),
            outputPath: outputPath,
            onProgress: (progress) {
              setState(() {
                operationProgress = progress;
              });
            },
            onStatus: (status) {
              setState(() {
                operationStatus = status;
              });
            },
          );
          break;
        default:
          throw 'Unsupported archive type: $archiveType';
      }
      
      setState(() {
        operationInProgress = false;
        if (activePaneType == PaneType.left) {
          leftSelectedFiles.clear();
        } else {
          rightSelectedFiles.clear();
        }
      });
      
      if (archiveResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archive created successfully: ${p.basename(outputPath)}'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate to archive location in opposite pane
        _navigateToPath(activePaneType == PaneType.left ? PaneType.right : PaneType.left, p.dirname(outputPath));
        _refreshPane(activePaneType == PaneType.left ? PaneType.right : PaneType.left);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archive creation failed: ${archiveResult.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        operationInProgress = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Archive creation error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _moveSelectedFiles() async {
    final sourceFiles = activePaneType == PaneType.left ? leftSelectedFiles : rightSelectedFiles;
    final destinationPath = activePaneType == PaneType.left ? rightPath : leftPath;
    
    if (sourceFiles.isEmpty) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Move'),
        content: Text('Move ${sourceFiles.length} selected files?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() {
      operationInProgress = true;
      operationProgress = 0.0;
      operationStatus = 'Preparing to move files...';
    });
    
    try {
      final result = await FileOperationsService.moveFiles(
        sourceFiles.toList(),
        destinationPath,
        (progress, currentFile) {
          setState(() {
            operationProgress = progress;
            operationStatus = 'Moving: ${p.basename(currentFile)}';
          });
        },
      );
      
      setState(() {
        operationInProgress = false;
        if (activePaneType == PaneType.left) {
          leftSelectedFiles.clear();
        } else {
          rightSelectedFiles.clear();
        }
      });
      
      // Refresh both panes
      _refreshBothPanes();
      
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully moved ${result.processedFiles.length} files')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Move failed: ${result.error}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      setState(() {
        operationInProgress = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Move error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _deleteSelectedFiles() async {
    final sourceFiles = activePaneType == PaneType.left ? leftSelectedFiles : rightSelectedFiles;
    
    if (sourceFiles.isEmpty) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Permanently delete ${sourceFiles.length} selected files?\n\nThis action cannot be undone!'),
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
    
    if (confirmed != true) return;
    
    setState(() {
      operationInProgress = true;
      operationProgress = 0.0;
      operationStatus = 'Preparing to delete files...';
    });
    
    try {
      final result = await FileOperationsService.deleteFiles(
        sourceFiles.toList(),
        (progress, currentFile) {
          setState(() {
            operationProgress = progress;
            operationStatus = 'Deleting: ${p.basename(currentFile)}';
          });
        },
      );
      
      setState(() {
        operationInProgress = false;
        if (activePaneType == PaneType.left) {
          leftSelectedFiles.clear();
        } else {
          rightSelectedFiles.clear();
        }
      });
      
      // Refresh current pane
      _refreshPane(activePaneType);
      
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully deleted ${result.processedFiles.length} files')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: ${result.error}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      setState(() {
        operationInProgress = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _addSelectedToGameLibrary() {
    final allSelected = [...leftSelectedFiles, ...rightSelectedFiles];
    final executables = allSelected.where((path) => _isExecutableFile(path)).toList();
    
    for (final exePath in executables) {
      widget.onAddToGameLibrary?.call(exePath);
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${executables.length} executables to game library')),
    );
    
    setState(() {
      leftSelectedFiles.clear();
      rightSelectedFiles.clear();
    });
  }

  void _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final folderName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Folder Name',
            hintText: 'Enter folder name',
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    
    if (folderName != null && folderName.isNotEmpty) {
      final currentPath = activePaneType == PaneType.left ? leftPath : rightPath;
      final newFolderPath = p.join(currentPath, folderName);
      
      try {
        final result = await FileOperationsService.createDirectory(newFolderPath);
        if (result.success) {
          _refreshPane(activePaneType);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Created folder: $folderName')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create folder: ${result.error}'), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating folder: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showPathEditor(PaneType pane, String currentPath) async {
    final controller = TextEditingController(text: currentPath);
    final newPath = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Path - ${pane == PaneType.left ? 'Left' : 'Right'} Pane'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Directory Path',
              hintText: 'Enter directory path',
            ),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Navigate'),
          ),
        ],
      ),
    );
    
    if (newPath != null && newPath.isNotEmpty && newPath != currentPath) {
      try {
        final directory = Directory(newPath);
        if (await directory.exists()) {
          _navigateToPath(pane, newPath);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Directory does not exist: $newPath'), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid path: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _getFavoriteDisplayName(String path) {
    final homeDir = Platform.environment['HOME'] ?? '/';
    
    if (path == homeDir) return 'Home';
    if (path == '/') return 'Root';
    if (path == p.join(homeDir, 'Downloads')) return 'Downloads';
    if (path == p.join(homeDir, 'Documents')) return 'Documents';
    if (path == p.join(homeDir, 'Desktop')) return 'Desktop';
    
    // For other paths, show the basename or full path if it's short
    if (path.length > 30) {
      return '...${path.substring(path.length - 27)}';
    }
    return path;
  }
  
  IconData _getFavoriteIcon(String path) {
    final homeDir = Platform.environment['HOME'] ?? '/';
    
    if (path == homeDir) return Icons.home;
    if (path == '/') return Icons.computer;
    if (path == p.join(homeDir, 'Downloads')) return Icons.download;
    if (path == p.join(homeDir, 'Documents')) return Icons.description;
    if (path == p.join(homeDir, 'Desktop')) return Icons.desktop_windows;
    
    return Icons.folder;
  }
  

  
  void _showContextMenu(PaneType pane, FileItem file) async {
    final result = await showMenu<FileManagerAction>(
      context: context,
      position: RelativeRect.fromLTRB(100, 100, 100, 100), // Will be positioned by tap location
      items: [
        if (file.isGameExecutable && !file.isInGameLibrary)
          const PopupMenuItem(
            value: FileManagerAction.addToGameLibrary,
            child: ListTile(
              leading: Icon(Icons.videogame_asset),
              title: Text('Add to Game Library'),
            ),
          ),
        const PopupMenuItem(
          value: FileManagerAction.copy,
          child: ListTile(
            leading: Icon(Icons.copy),
            title: Text('Copy to Other Pane'),
            subtitle: Text('Ctrl+C'),
          ),
        ),
        const PopupMenuItem(
          value: FileManagerAction.move,
          child: ListTile(
            leading: Icon(Icons.drive_file_move),
            title: Text('Move to Other Pane'),
            subtitle: Text('Ctrl+X'),
          ),
        ),
        const PopupMenuItem(
          value: FileManagerAction.rename,
          child: ListTile(
            leading: Icon(Icons.edit),
            title: Text('Rename'),
            subtitle: Text('F2'),
          ),
        ),
        const PopupMenuItem(
          value: FileManagerAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete, color: Colors.red),
            title: Text('Delete', style: TextStyle(color: Colors.red)),
            subtitle: Text('Delete'),
          ),
        ),
        const PopupMenuDivider(),
        if (file.isDirectory)
          const PopupMenuItem(
            value: FileManagerAction.openWith,
            child: ListTile(
              leading: Icon(Icons.folder_open),
              title: Text('Open in File Manager'),
            ),
          ),
        const PopupMenuItem(
          value: FileManagerAction.properties,
          child: ListTile(
            leading: Icon(Icons.info),
            title: Text('Properties'),
          ),
        ),
      ],
    );
    
    if (result != null) {
      await _handleContextAction(result, pane, file);
    }
  }
  
  Future<void> _handleContextAction(FileManagerAction action, PaneType pane, FileItem file) async {
    switch (action) {
      case FileManagerAction.addToGameLibrary:
        if (file.isGameExecutable) {
          widget.onAddToGameLibrary?.call(file.entity.path);
        }
        break;
      case FileManagerAction.copy:
        // Set selection and copy
        final selectedFiles = pane == PaneType.left ? leftSelectedFiles : rightSelectedFiles;
        selectedFiles.clear();
        selectedFiles.add(file.entity.path);
        _copySelectedFiles();
        break;
      case FileManagerAction.move:
        // Set selection and move
        final selectedFiles = pane == PaneType.left ? leftSelectedFiles : rightSelectedFiles;
        selectedFiles.clear();
        selectedFiles.add(file.entity.path);
        _moveSelectedFiles();
        break;
      case FileManagerAction.delete:
        // Set selection and delete
        final selectedFiles = pane == PaneType.left ? leftSelectedFiles : rightSelectedFiles;
        selectedFiles.clear();
        selectedFiles.add(file.entity.path);
        _deleteSelectedFiles();
        break;
      case FileManagerAction.rename:
        await _showRenameDialog(pane, file);
        break;
      case FileManagerAction.properties:
        await _showPropertiesDialog(file);
        break;
      case FileManagerAction.openWith:
        if (file.isDirectory) {
          _navigateToPath(pane, file.entity.path);
        }
        break;
      default:
        break;
    }
  }
  
  Future<void> _showRenameDialog(PaneType pane, FileItem file) async {
    final controller = TextEditingController(text: file.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename ${file.isDirectory ? 'Folder' : 'File'}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'New Name',
            hintText: 'Enter new name',
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
    
    if (newName != null && newName.isNotEmpty && newName != file.name) {
      try {
        final result = await FileOperationsService.renameFileOrDirectory(file.entity.path, newName);
        if (result.success) {
          _refreshPane(pane);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Renamed to: $newName')),
          );
          
          // Update game library path if this was a game executable
          if (file.isGameExecutable && file.isInGameLibrary) {
            final oldPath = file.entity.path;
            final newPath = p.join(p.dirname(oldPath), newName);
            widget.onUpdateGamePath?.call(oldPath, newPath);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to rename: ${result.error}'), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error renaming: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  Future<void> _showPropertiesDialog(FileItem file) async {
    try {
      final properties = await FileOperationsService.getProperties(file.entity.path);
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Properties - ${file.name}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPropertyRow('Name', properties['name']),
                _buildPropertyRow('Type', file.isDirectory ? 'Folder' : file.type),
                _buildPropertyRow('Path', properties['path']),
                _buildPropertyRow('Size', _formatFileSize(properties['size'])),
                _buildPropertyRow('Modified', properties['modified'].toString()),
                if (file.isDirectory) ...[
                  _buildPropertyRow('Items', '${properties['itemCount']} items'),
                  _buildPropertyRow('Files', '${properties['fileCount']} files'),
                  _buildPropertyRow('Folders', '${properties['directoryCount']} folders'),
                ],
                if (file.isGameExecutable)
                  _buildPropertyRow('Game Status', file.isInGameLibrary ? 'In Game Library' : 'Not in Library'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting properties: $e'), backgroundColor: Colors.red),
      );
    }
  }
  
  Widget _buildPropertyRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value.toString(),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
  
  void _showManageFavoritesDialog() async {
    final updatedFavorites = await showDialog<List<String>>(
      context: context,
      builder: (context) => _ManageFavoritesDialog(favorites: List.from(favoritePaths)),
    );
    
    if (updatedFavorites != null) {
      setState(() {
        favoritePaths = updatedFavorites;
      });
    }
  }
}

class _ManageFavoritesDialog extends StatefulWidget {
  final List<String> favorites;
  
  const _ManageFavoritesDialog({required this.favorites});
  
  @override
  State<_ManageFavoritesDialog> createState() => _ManageFavoritesDialogState();
}

class _ManageFavoritesDialogState extends State<_ManageFavoritesDialog> {
  late List<String> favorites;
  
  @override
  void initState() {
    super.initState();
    favorites = List.from(widget.favorites);
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Favorite Paths'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _addCustomPath,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Path'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: favorites.isEmpty
                  ? const Center(child: Text('No favorite paths'))
                  : ReorderableListView.builder(
                      itemCount: favorites.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex--;
                          final item = favorites.removeAt(oldIndex);
                          favorites.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final path = favorites[index];
                        final displayName = _getDisplayName(path);
                        return ListTile(
                          key: ValueKey(path),
                          leading: Icon(_getPathIcon(path)),
                          title: Text(displayName),
                          subtitle: path != displayName ? Text(path) : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                favorites.removeAt(index);
                              });
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(favorites),
          child: const Text('Save'),
        ),
      ],
    );
  }
  
  String _getDisplayName(String path) {
    final homeDir = Platform.environment['HOME'] ?? '/';
    
    if (path == homeDir) return 'Home';
    if (path == '/') return 'Root';
    if (path == p.join(homeDir, 'Downloads')) return 'Downloads';
    if (path == p.join(homeDir, 'Documents')) return 'Documents';
    if (path == p.join(homeDir, 'Desktop')) return 'Desktop';
    
    return p.basename(path);
  }
  
  IconData _getPathIcon(String path) {
    final homeDir = Platform.environment['HOME'] ?? '/';
    
    if (path == homeDir) return Icons.home;
    if (path == '/') return Icons.computer;
    if (path == p.join(homeDir, 'Downloads')) return Icons.download;
    if (path == p.join(homeDir, 'Documents')) return Icons.description;
    if (path == p.join(homeDir, 'Desktop')) return Icons.desktop_windows;
    
    return Icons.folder;
  }
  
  void _addCustomPath() async {
    final controller = TextEditingController();
    final newPath = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Custom Path'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Directory Path',
            hintText: 'Enter full directory path',
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
    
    if (newPath != null && newPath.isNotEmpty) {
      try {
        if (await Directory(newPath).exists()) {
          if (!favorites.contains(newPath)) {
            setState(() {
              favorites.add(newPath);
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Path already exists in favorites')),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Directory does not exist: $newPath')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid path: $e')),
        );
      }
    }
  }
}

class _BackupDialog extends StatefulWidget {
  final List<String> selectedFiles;

  const _BackupDialog({
    required this.selectedFiles,
  });

  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  final _nameController = TextEditingController();
  final _dirController = TextEditingController();
  String _selectedDirectory = '';

  @override
  void initState() {
    super.initState();
    // Default backup directory to home/Backups
    final homeDir = Platform.environment['HOME'] ?? '/';
    _selectedDirectory = p.join(homeDir, 'Backups');
    _dirController.text = _selectedDirectory;
    
    // Default backup name based on selection
    if (widget.selectedFiles.length == 1) {
      _nameController.text = p.basenameWithoutExtension(widget.selectedFiles.first);
    } else {
      _nameController.text = 'backup_${widget.selectedFiles.length}_items';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dirController.dispose();
    super.dispose();
  }

  Future<void> _selectBackupDirectory() async {
    final selectedDir = await showDialog<String>(
      context: context,
      builder: (context) => _DirectoryPickerDialog(
        initialPath: _selectedDirectory,
      ),
    );
    
    if (selectedDir != null) {
      setState(() {
        _selectedDirectory = selectedDir;
        _dirController.text = selectedDir;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.backup, color: Colors.orange),
          SizedBox(width: 8),
          Text('Create Backup'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Creating backup of ${widget.selectedFiles.length} item${widget.selectedFiles.length == 1 ? '' : 's'}:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.selectedFiles.take(3).map((file) => 
                  Text(
                    p.basename(file),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ).toList()
                  ..addAll(widget.selectedFiles.length > 3 ? [
                    Text(
                      '... and ${widget.selectedFiles.length - 3} more',
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    )
                  ] : []),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Backup Name',
                hintText: 'Enter backup name (without extension)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dirController,
              decoration: InputDecoration(
                labelText: 'Backup Directory',
                hintText: 'Select backup destination',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: _selectBackupDirectory,
                ),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Backup will be compressed using zstd compression (.tar.zst)',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _nameController.text.trim().isNotEmpty && _selectedDirectory.isNotEmpty
              ? () {
                  Navigator.of(context).pop({
                    'backupName': _nameController.text.trim(),
                    'backupDir': _selectedDirectory,
                  });
                }
              : null,
          icon: const Icon(Icons.backup),
          label: const Text('Create Backup'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange[600],
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _ArchiveCreationDialog extends StatefulWidget {
  final List<String> selectedFiles;

  const _ArchiveCreationDialog({
    required this.selectedFiles,
  });

  @override
  State<_ArchiveCreationDialog> createState() => _ArchiveCreationDialogState();
}

class _ArchiveCreationDialogState extends State<_ArchiveCreationDialog> {
  final _nameController = TextEditingController();
  final _dirController = TextEditingController();
  String _selectedDirectory = '';
  String _selectedType = 'zip';

  @override
  void initState() {
    super.initState();
    // Default archive directory to current directory
    if (widget.selectedFiles.isNotEmpty) {
      _selectedDirectory = p.dirname(widget.selectedFiles.first);
      _dirController.text = _selectedDirectory;
    }
    
    // Default archive name based on selection
    if (widget.selectedFiles.length == 1) {
      _nameController.text = p.basenameWithoutExtension(widget.selectedFiles.first);
    } else {
      _nameController.text = 'archive_${widget.selectedFiles.length}_items';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dirController.dispose();
    super.dispose();
  }

  Future<void> _selectOutputDirectory() async {
    final selectedDir = await showDialog<String>(
      context: context,
      builder: (context) => _DirectoryPickerDialog(
        initialPath: _selectedDirectory,
      ),
    );
    
    if (selectedDir != null) {
      setState(() {
        _selectedDirectory = selectedDir;
        _dirController.text = selectedDir;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.archive, color: Colors.purple),
          SizedBox(width: 8),
          Text('Create Archive'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Creating archive from ${widget.selectedFiles.length} item${widget.selectedFiles.length == 1 ? '' : 's'}:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.selectedFiles.take(3).map((file) => 
                  Text(
                    p.basename(file),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ).toList()
                  ..addAll(widget.selectedFiles.length > 3 ? [
                    Text(
                      '... and ${widget.selectedFiles.length - 3} more',
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    )
                  ] : []),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Archive Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'zip', child: Text('ZIP (.zip)')),
                DropdownMenuItem(value: 'rar', child: Text('RAR (.rar)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedType = value;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Archive Name',
                hintText: 'Enter archive name (without extension)',
                border: const OutlineInputBorder(),
                suffixText: '.$_selectedType',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dirController,
              decoration: InputDecoration(
                labelText: 'Output Directory',
                hintText: 'Select output destination',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: _selectOutputDirectory,
                ),
              ),
              readOnly: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _nameController.text.trim().isNotEmpty && _selectedDirectory.isNotEmpty
              ? () {
                  final outputPath = p.join(_selectedDirectory, '${_nameController.text.trim()}.$_selectedType');
                  Navigator.of(context).pop({
                    'outputPath': outputPath,
                    'archiveType': _selectedType,
                  });
                }
              : null,
          icon: const Icon(Icons.archive),
          label: const Text('Create Archive'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple[600],
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _DirectoryPickerDialog extends StatefulWidget {
  final String initialPath;

  const _DirectoryPickerDialog({
    required this.initialPath,
  });

  @override
  State<_DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<_DirectoryPickerDialog> {
  late String currentPath;
  List<Directory> directories = [];

  @override
  void initState() {
    super.initState();
    currentPath = widget.initialPath;
    _loadDirectories();
  }

  Future<void> _loadDirectories() async {
    try {
      final dir = Directory(currentPath);
      final entities = await dir.list().toList();
      setState(() {
        directories = entities
            .where((e) => e is Directory)
            .cast<Directory>()
            .toList()
          ..sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      });
    } catch (e) {
      setState(() {
        directories = [];
      });
    }
  }

  void _navigateToParent() {
    final parent = p.dirname(currentPath);
    if (parent != currentPath) {
      setState(() {
        currentPath = parent;
      });
      _loadDirectories();
    }
  }

  void _navigateToDirectory(String path) {
    setState(() {
      currentPath = path;
    });
    _loadDirectories();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Backup Directory'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            // Current path
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: p.dirname(currentPath) != currentPath ? _navigateToParent : null,
                    tooltip: 'Go up',
                  ),
                  Expanded(
                    child: Text(
                      currentPath,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Directory list
            Expanded(
              child: ListView.builder(
                itemCount: directories.length,
                itemBuilder: (context, index) {
                  final dir = directories[index];
                  return ListTile(
                    leading: const Icon(Icons.folder, color: Colors.blue),
                    title: Text(p.basename(dir.path)),
                    onTap: () => _navigateToDirectory(dir.path),
                    dense: true,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(currentPath),
          child: const Text('Select'),
        ),
      ],
    );
  }
}

enum PaneType { left, right }