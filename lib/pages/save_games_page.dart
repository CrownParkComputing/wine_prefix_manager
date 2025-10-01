import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../models/prefix_models.dart';
import '../providers/prefix_provider.dart';
import '../services/log_service.dart';
import '../utils/logger.dart';

class SaveGamesPage extends StatefulWidget {
  const SaveGamesPage({super.key});


  @override
  State<SaveGamesPage> createState() => _SaveGamesPageState();
}

class _SaveGamesPageState extends State<SaveGamesPage> {
  List<SaveGameInfo> _saveGames = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedGameFilter = 'All Games';
  List<String> _gameNames = [];
  void _logError(String message, [Object? error, StackTrace? stackTrace]) =>
      logError('[SaveGamesPage] $message', error, stackTrace);

  @override
  void initState() {
    super.initState();
    _loadSaveGames();
  }

  Future<void> _loadSaveGames() async {
    setState(() => _isLoading = true);
    
    final prefixProvider = Provider.of<PrefixProvider>(context, listen: false);
    final logService = Provider.of<LogService>(context, listen: false);
    
    List<SaveGameInfo> allSaveGames = [];
    List<String> gameNames = ['All Games'];
    
    try {
      final games = prefixProvider.getAllGamesFromPrefixes();
      logService.log('Found ${games.length} games in database');
      
      for (final game in games) {
        logService.log('Checking save data for game: ${game.exe.name} in prefix: ${game.prefix.name}');
        gameNames.add(game.exe.name);
        
        // Check save data paths defined in the game
        for (final savePath in game.exe.saveDataPaths) {
          final fullPath = p.join(game.prefix.path, 'drive_c', savePath);
          if (await Directory(fullPath).exists()) {
            final fileCount = await _countFiles(fullPath);
            if (fileCount > 0) { // Only include if there are actual files
              final saveGame = SaveGameInfo(
                gameName: game.exe.name,
                prefixName: game.prefix.name,
                savePath: fullPath,
                relativePath: savePath,
                lastModified: await _getLastModified(fullPath),
                fileCount: fileCount,
                totalSize: await _calculateSize(fullPath),
                isInUserDirectory: _isInUserDirectory(fullPath, game.prefix.path),
              );
              allSaveGames.add(saveGame);
              logService.log('Found save data in defined path: $fullPath ($fileCount files)');
            }
          }
        }
        
        // Check comprehensive save game locations within Wine prefix
        final saveLocations = await _findSaveGameLocations(game);
        logService.log('Found ${saveLocations.length} potential save locations for ${game.exe.name}');
        for (final location in saveLocations) {
          final fileCount = await _countFiles(location);
          if (fileCount > 0) { // Only include if there are actual files
            final saveGame = SaveGameInfo(
              gameName: game.exe.name,
              prefixName: game.prefix.name,
              savePath: location,
              relativePath: p.relative(location, from: game.prefix.path),
              lastModified: await _getLastModified(location),
              fileCount: fileCount,
              totalSize: await _calculateSize(location),
              isInUserDirectory: _isInUserDirectory(location, game.prefix.path),
            );
            allSaveGames.add(saveGame);
            logService.log('Found save data in detected location: $location ($fileCount files)');
          }
        }
      }
      
      // Check Linux native save game locations
      final linuxSaves = await _findLinuxSaveGames(prefixProvider);
      allSaveGames.addAll(linuxSaves);
      
      setState(() {
        _saveGames = allSaveGames;
        _gameNames = gameNames;
        _isLoading = false;
      });
      
      logService.log('Found ${allSaveGames.length} save game locations with actual files');
      
    } catch (e) {
      logService.log('Error loading save games: $e', LogLevel.error);
      setState(() => _isLoading = false);
    }
  }

  Future<List<String>> _findSaveGameLocations(GameEntry game) async {
    final prefixPath = game.prefix.path;
    final gameName = game.exe.name;
    final gameNameLower = gameName.toLowerCase().replaceAll(' ', '');
    final List<String> locations = [];
    
    // Create variations of the game name for better matching
    final gameNameVariations = {
      gameName,
      gameNameLower,
      gameName.replaceAll(' ', ''),
      gameName.replaceAll(' ', '_'),
      gameName.replaceAll(' ', '-'),
      // Common game name patterns
      if (gameName.contains('Tokyo')) 'TokyoXtremeRacer',
      if (gameName.contains('SHf')) 'SHf',
      if (gameName.contains('Hell')) 'HellIsUs',
      if (gameName.contains('War')) 'Coalition',
      if (gameName.contains('Golf')) 'EverybodysGolfHotShots',
    }; // Remove duplicates
    
    // Generate paths for all game name variations
    final commonPaths = <String>[];
    
    // Base user profile locations
    commonPaths.addAll([
      p.join(prefixPath, 'drive_c', 'users', 'crossover', 'AppData', 'Local'),
      p.join(prefixPath, 'drive_c', 'users', 'crossover', 'AppData', 'Roaming'),
      p.join(prefixPath, 'drive_c', 'users', 'crossover', 'Saved Games'),
      p.join(prefixPath, 'drive_c', 'users', 'crossover', 'Documents', 'My Games'),
      p.join(prefixPath, 'drive_c', 'users', 'crossover', 'Documents'),
      p.join(prefixPath, 'drive_c', 'ProgramData'),
      p.join(prefixPath, 'drive_c', 'users', 'steamuser', 'AppData', 'Local'),
      p.join(prefixPath, 'drive_c', 'users', 'steamuser', 'AppData', 'Roaming'),
      p.join(prefixPath, 'drive_c', 'users', 'steamuser', 'Saved Games'),
      p.join(prefixPath, 'drive_c', 'users', 'steamuser', 'Documents'),
    ]);
    
    // Generate game-specific paths for all variations
    for (final variation in gameNameVariations) {
      commonPaths.addAll([
        // Crossover user paths
        p.join(prefixPath, 'drive_c', 'users', 'crossover', 'AppData', 'Local', variation),
        p.join(prefixPath, 'drive_c', 'users', 'crossover', 'AppData', 'Roaming', variation),
        p.join(prefixPath, 'drive_c', 'users', 'crossover', 'Saved Games', variation),
        p.join(prefixPath, 'drive_c', 'users', 'crossover', 'Documents', variation),
        
        // Steamuser paths
        p.join(prefixPath, 'drive_c', 'users', 'steamuser', 'AppData', 'Local', variation),
        p.join(prefixPath, 'drive_c', 'users', 'steamuser', 'AppData', 'Roaming', variation),
        p.join(prefixPath, 'drive_c', 'users', 'steamuser', 'Saved Games', variation),
        p.join(prefixPath, 'drive_c', 'users', 'steamuser', 'Documents', variation),
        
        // Unreal Engine save locations
        p.join(prefixPath, 'drive_c', 'users', 'steamuser', 'AppData', 'Local', variation, 'Saved', 'SaveGames'),
        p.join(prefixPath, 'drive_c', 'users', 'crossover', 'AppData', 'Local', variation, 'Saved', 'SaveGames'),
      ]);
    }
    
    // Check each path and add if it exists and contains files
    for (final path in commonPaths) {
      if (await Directory(path).exists()) {
        final fileCount = await _countFiles(path);
        if (fileCount > 0) {
          locations.add(path);
        }
      }
    }
    
    // Also check for any subdirectories that might contain save files
    final driveC = Directory(p.join(prefixPath, 'drive_c'));
    if (await driveC.exists()) {
      await for (final entity in driveC.list(recursive: true)) {
        if (entity is Directory) {
          final dirName = entity.path.split('/').last.toLowerCase();
          final fullPath = entity.path.toLowerCase();
          
          // Check if this directory matches any of our game name variations
          bool matchesGame = false;
          for (final variation in gameNameVariations) {
            if (dirName.contains(variation.toLowerCase()) || 
                fullPath.contains(variation.toLowerCase())) {
              matchesGame = true;
              break;
            }
          }
          
          // Look for directories that might contain save files
          if (matchesGame || 
              dirName.contains('save') || 
              dirName.contains('game') ||
              dirName.contains('data') ||
              fullPath.contains('/saved/savegames/') ||
              fullPath.contains('/savedgames/') ||
              fullPath.contains('/savedata/') ||
              fullPath.contains('/saved/')) {
            final fileCount = await _countFiles(entity.path);
            if (fileCount > 0) {
              locations.add(entity.path);
            }
          }
        }
      }
    }
    
    // Check for additional save patterns that might not match game name exactly
    final additionalPaths = [
      // Check for Coalition/WarGame pattern
      p.join(prefixPath, 'drive_c', 'users', 'steamuser', 'AppData', 'Local', 'Coalition', 'WarGame', 'SaveData'),
      p.join(prefixPath, 'drive_c', 'users', 'crossover', 'AppData', 'Local', 'Coalition', 'WarGame', 'SaveData'),
      
      // Check for UnrealEngine saves
      p.join(prefixPath, 'drive_c', 'users', 'steamuser', 'AppData', 'Local', 'UnrealEngine'),
      p.join(prefixPath, 'drive_c', 'users', 'crossover', 'AppData', 'Local', 'UnrealEngine'),
      
      // Check for LocalLow saves
      p.join(prefixPath, 'drive_c', 'users', 'steamuser', 'AppData', 'LocalLow'),
      p.join(prefixPath, 'drive_c', 'users', 'crossover', 'AppData', 'LocalLow'),
    ];
    
    for (final path in additionalPaths) {
      if (await Directory(path).exists()) {
        final fileCount = await _countFiles(path);
        if (fileCount > 0) {
          locations.add(path);
        }
      }
    }
    
    return locations;
  }
  
  Future<List<SaveGameInfo>> _findLinuxSaveGames(PrefixProvider prefixProvider) async {
    final List<SaveGameInfo> linuxSaves = [];
    final homeDir = Platform.environment['HOME'] ?? '';
    
    if (homeDir.isEmpty) return linuxSaves;
    
    try {
      final games = prefixProvider.getAllGamesFromPrefixes();
      
      for (final game in games) {
        final gameName = game.exe.name.toLowerCase().replaceAll(' ', '');
        
        // Common Linux save game locations
        final linuxPaths = [
          // Steam save locations
          p.join(homeDir, '.steam', 'steam', 'userdata'),
          p.join(homeDir, '.local', 'share', 'Steam', 'userdata'),
          
          // Game-specific locations
          p.join(homeDir, '.local', 'share', gameName),
          p.join(homeDir, '.config', gameName),
          p.join(homeDir, '.cache', gameName),
          p.join(homeDir, 'Documents', gameName),
          p.join(homeDir, 'Documents', 'My Games', gameName),
          
          // XDG directories
          p.join(homeDir, '.local', 'share', 'games', gameName),
          p.join(homeDir, '.config', 'games', gameName),
          
          // Common save file patterns
          p.join(homeDir, '.wine', 'drive_c', 'users', Platform.environment['USER'] ?? 'user', 'Documents'),
          p.join(homeDir, '.wine', 'drive_c', 'users', Platform.environment['USER'] ?? 'user', 'AppData'),
        ];
        
        for (final path in linuxPaths) {
          if (await Directory(path).exists()) {
            final fileCount = await _countFiles(path);
            if (fileCount > 0) {
              final saveGame = SaveGameInfo(
                gameName: game.exe.name,
                prefixName: 'Linux Native',
                savePath: path,
                relativePath: p.relative(path, from: homeDir),
                lastModified: await _getLastModified(path),
                fileCount: fileCount,
                totalSize: await _calculateSize(path),
                isInUserDirectory: _isInUserDirectory(path, homeDir),
              );
              linuxSaves.add(saveGame);
            }
          }
        }
      }
    } catch (e, stackTrace) {
      // Log error but don't fail the entire operation
      _logError('Error checking Linux save games', e, stackTrace);
    }
    
    return linuxSaves;
  }

  Future<DateTime> _getLastModified(String path) async {
    try {
      final dir = Directory(path);
      final stat = await dir.stat();
      return stat.modified;
    } catch (e) {
      return DateTime.now();
    }
  }

  Future<int> _countFiles(String path) async {
    try {
      int count = 0;
      await for (final entity in Directory(path).list(recursive: true)) {
        if (entity is File) {
          count++;
        }
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  Future<int> _calculateSize(String path) async {
    try {
      int totalSize = 0;
      await for (final entity in Directory(path).list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  List<SaveGameInfo> get _filteredSaveGames {
    var filtered = _saveGames;
    
    if (_selectedGameFilter != 'All Games') {
      filtered = filtered.where((save) => save.gameName == _selectedGameFilter).toList();
    }
    
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((save) => 
        save.gameName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        save.prefixName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        save.relativePath.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
    
    return filtered;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Save Games'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSaveGames,
            tooltip: 'Refresh Save Games',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and filter bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Column(
              children: [
                // Search bar
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search save games...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                // Game filter dropdown
                Row(
                  children: [
                    const Text('Filter by game: '),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _selectedGameFilter,
                        isExpanded: true,
                        items: _gameNames.map((String game) {
                          return DropdownMenuItem<String>(
                            value: game,
                            child: Text(game),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedGameFilter = newValue!;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Save games list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSaveGames.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.save_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurface.withValues(alpha:0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No save games found',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha:0.7),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Save games will appear here when detected',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha:0.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredSaveGames.length,
                        itemBuilder: (context, index) {
                          final saveGame = _filteredSaveGames[index];
                          return _buildSaveGameCard(saveGame);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveGameCard(SaveGameInfo saveGame) {
    final theme = Theme.of(context);
    
    // Determine colors and styling based on whether it's in user directory
    final isInUserDir = saveGame.isInUserDirectory;
    final cardColor = isInUserDir 
        ? null // Use default card color for user directory saves
        : Colors.orange.withValues(alpha:0.1); // Highlight non-user directory saves
    final borderColor = isInUserDir 
        ? null 
        : Colors.orange.withValues(alpha:0.3);
    final iconColor = isInUserDir 
        ? theme.colorScheme.primary 
        : Colors.orange;
    final backgroundColor = isInUserDir 
        ? theme.colorScheme.primary.withValues(alpha:0.1)
        : Colors.orange.withValues(alpha:0.1);
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: cardColor,
      shape: borderColor != null 
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: borderColor, width: 1),
            )
          : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: backgroundColor,
          child: Icon(
            isInUserDir ? Icons.save : Icons.warning,
            color: iconColor,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                saveGame.gameName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            // Directory type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isInUserDir 
                    ? Colors.green.withValues(alpha:0.2)
                    : Colors.orange.withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isInUserDir 
                      ? Colors.green.withValues(alpha:0.5)
                      : Colors.orange.withValues(alpha:0.5),
                  width: 1,
                ),
              ),
              child: Text(
                isInUserDir ? 'User Dir' : 'System Dir',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isInUserDir ? Colors.green[700] : Colors.orange[700],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.visibility,
              size: 16,
              color: theme.colorScheme.primary.withValues(alpha:0.7),
            ),
            const SizedBox(width: 4),
            Text(
              'Tap to view files',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary.withValues(alpha:0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prefix: ${saveGame.prefixName}'),
            Text('Path: ${saveGame.relativePath}'),
            if (!isInUserDir) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.withValues(alpha:0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber,
                      size: 14,
                      color: Colors.orange[700],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Save data in system directory - will be cleaned up on next launch',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.file_copy,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha:0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  '${saveGame.fileCount} files',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.storage,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha:0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  _formatFileSize(saveGame.totalSize),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha:0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  'Modified: ${_formatDate(saveGame.lastModified)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'backup':
                    _backupSaveGame(saveGame);
                    break;
                  case 'restore':
                    _restoreSaveGame(saveGame);
                    break;
                  case 'delete':
                    _deleteSaveGame(saveGame);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'backup',
                  child: ListTile(
                    leading: Icon(Icons.backup),
                    title: Text('Backup Save'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'restore',
                  child: ListTile(
                    leading: Icon(Icons.restore),
                    title: Text('Restore Save'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text('Delete Folder', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        onTap: () => _showSaveGameFiles(saveGame),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  /// Determines if a save path is in a user directory (as opposed to system directories)
  bool _isInUserDirectory(String savePath, String prefixPath) {
    // Convert to lowercase for case-insensitive comparison
    final lowerPath = savePath.toLowerCase();
    
    // Check if the path is within user directories
    final userDirectories = [
      'users/steamuser',
      'users/crossover', 
      'users/public',
      'users/defaultuser',
      'users/user',
    ];
    
    // Check if any user directory is in the path
    for (final userDir in userDirectories) {
      if (lowerPath.contains(userDir.toLowerCase())) {
        return true;
      }
    }
    
    // Check for Linux native user directories
    final homeDir = Platform.environment['HOME'] ?? '';
    if (homeDir.isNotEmpty && lowerPath.contains(homeDir.toLowerCase())) {
      return true;
    }
    
    // Check for Steam userdata directories
    if (lowerPath.contains('.steam/steam/userdata') || 
        lowerPath.contains('.local/share/steam/userdata')) {
      return true;
    }
    
    // If none of the above, it's likely in a system directory
    return false;
  }

  void _showSaveGameFiles(SaveGameInfo saveGame) {
    final logService = Provider.of<LogService>(context, listen: false);
    logService.log('Showing save game files for: ${saveGame.gameName} at ${saveGame.savePath}');
    
    showDialog(
      context: context,
      builder: (context) => SaveGameFilesDialog(saveGame: saveGame),
    );
  }

  void _backupSaveGame(SaveGameInfo saveGame) {
    final logService = Provider.of<LogService>(context, listen: false);
    logService.log('Backing up save game: ${saveGame.gameName}');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Backup functionality for ${saveGame.gameName} - Coming soon!'),
      ),
    );
  }

  void _restoreSaveGame(SaveGameInfo saveGame) {
    final logService = Provider.of<LogService>(context, listen: false);
    logService.log('Restoring save game: ${saveGame.gameName}');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Restore functionality for ${saveGame.gameName} - Coming soon!'),
      ),
    );
  }

  void _deleteSaveGame(SaveGameInfo saveGame) {
    final logService = Provider.of<LogService>(context, listen: false);
    logService.log('Prompting delete confirmation for save game: ${saveGame.gameName}');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Save Game Folder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete this save game folder?'),
            const SizedBox(height: 16),
            Text(
              'Game: ${saveGame.gameName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('Path: ${saveGame.savePath}'),
            Text('Files: ${saveGame.fileCount}'),
            const SizedBox(height: 16),
            const Text(
              'This action cannot be undone!',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _performDelete(saveGame);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _performDelete(SaveGameInfo saveGame) async {
    final logService = Provider.of<LogService>(context, listen: false);
    
    try {
      logService.log('Deleting save game folder: ${saveGame.savePath}');
      
      final directory = Directory(saveGame.savePath);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
        logService.log('Successfully deleted save game folder: ${saveGame.savePath}');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully deleted save game folder for ${saveGame.gameName}'),
              backgroundColor: Colors.green,
            ),
          );
        }
        
        // Reload the save games list
        _loadSaveGames();
      } else {
        logService.log('Save game folder does not exist: ${saveGame.savePath}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Save game folder not found: ${saveGame.gameName}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      logService.log('Error deleting save game folder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting save game folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class SaveGameFilesDialog extends StatefulWidget {
  final SaveGameInfo saveGame;

  const SaveGameFilesDialog({super.key, required this.saveGame});


  @override
  State<SaveGameFilesDialog> createState() => _SaveGameFilesDialogState();
}

class _SaveGameFilesDialogState extends State<SaveGameFilesDialog> {
  List<FileSystemEntity> _files = [];
  bool _isLoading = true;

  void _logDebug(String message) => logDebug('[SaveGameFilesDialog] $message');
  void _logInfo(String message) => logInfo('[SaveGameFilesDialog] $message');
  void _logWarning(String message) => logWarning('[SaveGameFilesDialog] $message');
  void _logError(String message, [Object? error, StackTrace? stackTrace]) =>
      logError('[SaveGameFilesDialog] $message', error, stackTrace);

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    
    try {
      _logDebug('Loading files from: ${widget.saveGame.savePath}');
      final directory = Directory(widget.saveGame.savePath);
      if (await directory.exists()) {
        _logDebug('Directory exists, listing files...');
        final files = await directory.list().toList();
        _logDebug('Found ${files.length} files/directories');
        files.sort((a, b) {
          if (a is Directory && b is File) return -1;
          if (a is File && b is Directory) return 1;
          return a.path.compareTo(b.path);
        });
        setState(() {
          _files = files;
          _isLoading = false;
        });
        _logInfo('Files loaded successfully: ${_files.length} items');
      } else {
        _logWarning('Directory does not exist: ${widget.saveGame.savePath}');
        setState(() {
          _files = [];
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      _logError('Error loading files', e, stackTrace);
      setState(() {
        _files = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.save, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${widget.saveGame.gameName} - Save Files',
              style: theme.textTheme.titleLarge,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Path: ${widget.saveGame.savePath}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha:0.7),
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_files.isEmpty)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: 48,
                      color: theme.colorScheme.onSurface.withValues(alpha:0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No files found',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha:0.7),
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    return _buildFileItem(file);
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildFileItem(FileSystemEntity file) {
    final theme = Theme.of(context);
    final directory = file is Directory ? file : null;
    final fileName = file.path.split('/').last;
    
    return ListTile(
      leading: Icon(
        directory != null ? Icons.folder : Icons.description,
        color: directory != null ? Colors.orange : theme.colorScheme.primary,
      ),
      title: Text(fileName),
      subtitle: directory != null 
          ? const Text('Folder')
          : Text(_formatFileSize(file.statSync().size)),
      trailing: directory != null 
          ? const Icon(Icons.arrow_forward_ios, size: 16)
          : null,
      onTap: directory != null 
          ? () => _openSubfolder(directory)
          : null,
    );
  }

  void _openSubfolder(Directory directory) {
    // Show subfolder contents in a new dialog
    showDialog(
      context: context,
      builder: (context) => SaveGameFilesDialog(
        saveGame: SaveGameInfo(
          gameName: widget.saveGame.gameName,
          prefixName: widget.saveGame.prefixName,
          savePath: directory.path,
          relativePath: p.relative(directory.path, from: widget.saveGame.savePath),
          lastModified: DateTime.now(),
          fileCount: 0,
          totalSize: 0,
          isInUserDirectory: widget.saveGame.isInUserDirectory,
        ),
      ),
    );
  }


  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class SaveGameInfo {
  final String gameName;
  final String prefixName;
  final String savePath;
  final String relativePath;
  final DateTime lastModified;
  final int fileCount;
  final int totalSize;
  final bool isInUserDirectory;

  SaveGameInfo({
    required this.gameName,
    required this.prefixName,
    required this.savePath,
    required this.relativePath,
    required this.lastModified,
    required this.fileCount,
    required this.totalSize,
    required this.isInUserDirectory,
  });
}
