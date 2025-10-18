// filepath: /home/jon/wine_prefix_manager/lib/pages/game_library_page.dart
import 'package:flutter/material.dart';
import 'package:collection/collection.dart'; // Import for groupBy
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../widgets/game_card.dart'; // Import GameCard for GameLaunchState
import '../widgets/game_info_modal.dart'; // Import GameInfoModal
import '../widgets/game_settings_modal.dart'; // Import GameSettingsModal
import '../services/ui_action_service.dart'; // Import UIActionService for addExecutableToPrefix
import 'package:provider/provider.dart'; // Import Provider to access UIActionService
import '../pages/home_page.dart'; // Import for ViewMode enum

class GameLibraryPage extends StatelessWidget {
  final List<GameEntry> games;
  final Function(WinePrefix, ExeEntry) onLaunchGame;
  final Function(GameEntry, String?) onSaveLaunchOptions;
  final Function(GameEntry, String?) onChangeCategory;
  final Function(GameEntry, bool) onToggleWorkingStatus;
  final Function(GameEntry)? onUpdateMetadata;
  final Function(GameEntry)? onDelete;
  final Function(GameEntry, ExeEntry)? onUpdateCompressedGame;
  final Function(String?)? onGenreSelected;
  final String? selectedGenre;
  final CoverSize coverSize;
  final ViewMode currentViewMode;
  final Map<String, GameLaunchState> gameLaunchStates;
  final Function(GameEntry) onStopGame;
  final VoidCallback? onRefresh;
  final bool isRefreshing;
  final VoidCallback? onShowSettings;
  final VoidCallback? onToggleTheme;
  final VoidCallback? onToggleViewMode;
  final bool isDarkMode;

  const GameLibraryPage({
    super.key,
    required this.games,
    required this.onLaunchGame,
    required this.onSaveLaunchOptions,
    required this.onChangeCategory,
    required this.onToggleWorkingStatus,
    this.onUpdateMetadata,
    this.onDelete,
    this.onUpdateCompressedGame,
    this.onGenreSelected,
    this.selectedGenre,
    this.coverSize = CoverSize.medium,
    this.currentViewMode = ViewMode.grid,
    required this.gameLaunchStates,
    required this.onStopGame,
    this.onRefresh,
    this.isRefreshing = false,
    this.onShowSettings,
    this.onToggleTheme,
    this.onToggleViewMode,
    this.isDarkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // Apply genre filter first
    final filteredGames = selectedGenre != null
        ? games.where((game) => game.exe.category == selectedGenre).toList()
        : games;

    // Group filtered games by prefix with error handling
    Map<WinePrefix, List<GameEntry>> groupedGames;
    try {
      groupedGames = groupBy<GameEntry, WinePrefix>(
        filteredGames,
        (game) => game.prefix,
      );
    } catch (e) {
      // If grouping fails (e.g., during prefix operations), show loading state
      return Scaffold(
        appBar: AppBar(
          title: const Text('Game Library'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Sort prefixes by name for consistent order
    final sortedPrefixes = groupedGames.keys.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Library'),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          // View mode toggle button (always shown)
          IconButton(
            icon: Icon(
              currentViewMode == ViewMode.grid
                  ? Icons.grid_view
                  : currentViewMode == ViewMode.list
                      ? Icons.view_list
                      : Icons.view_carousel,
            ),
            tooltip: 'Switch View (${currentViewMode.name})',
            onPressed: onToggleViewMode,
          ),
          // Theme toggle button (always shown)
          IconButton(
            icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
            tooltip: isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: onToggleTheme,
          ),
          // Settings button (always shown)
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Game Library Settings',
            onPressed: onShowSettings,
          ),
          // Refresh button (always shown)
          IconButton(
            icon: isRefreshing 
              ? const SizedBox(
                  width: 24, 
                  height: 24, 
                  child: CircularProgressIndicator(strokeWidth: 2)
                ) 
              : const Icon(Icons.refresh),
            tooltip: 'Refresh Game Library',
            onPressed: isRefreshing ? null : onRefresh,
          ),
        ],
      ),
      body: Column(
        children: [
          // Display current filter if one is selected
          if (selectedGenre != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: Text('Category: ${selectedGenre!}'),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    if (onGenreSelected != null) onGenreSelected!(null);
                  },
                ),
              ),
            ),
          // Game List Area
          Expanded(
            child: filteredGames.isEmpty
                ? Center( // Show message if no games match filter or no games exist
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.sports_esports_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          selectedGenre != null
                              ? 'No games found in category "$selectedGenre"'
                              : 'No games found in library',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add games via the Manage tab',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder( // Use ListView for prefix groups
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    itemCount: sortedPrefixes.length,
                    itemBuilder: (context, index) {
                      final prefix = sortedPrefixes[index];
                      final gamesInPrefix = groupedGames[prefix]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Prefix Header with Add Executable Button
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  prefix.name,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                // Add buttons for this prefix
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Add EXE button
                                    IconButton(
                                      icon: const Icon(Icons.add),
                                      tooltip: 'Add Executable',
                                      onPressed: () {
                                        final navigatorContext = Navigator.of(context).context;
                                        _addExecutableToPrefix(navigatorContext, prefix);
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Grid for games within this prefix
                          GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            shrinkWrap: true, // Important for GridView inside ListView
                            physics: const NeverScrollableScrollPhysics(), // Disable GridView scrolling
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: _calculateCrossAxisCount(MediaQuery.of(context).size.width, coverSize),
                              childAspectRatio: _getAspectRatio(coverSize),
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: gamesInPrefix.length,
                            itemBuilder: (context, gameIndex) {
                              final game = gamesInPrefix[gameIndex];
                              // Get the launch state for this specific game
                              final launchState = gameLaunchStates[game.exe.path] ?? GameLaunchState.idle;

                              return Card( // Removed GestureDetector, GameCard handles taps
                                elevation: 4,
                                clipBehavior: Clip.antiAlias,
                                child: GameCard(
                                  game: game,
                                  coverSize: coverSize, // Pass cover size to GameCard
                                  onShowInfo: (g) => _showGameInfo(context, g), // Pass info callback
                                  onShowSettings: (g) => _showGameSettings(context, g), // Pass settings callback
                                  onLaunch: (g) => onLaunchGame(g.prefix, g.exe), // Pass launch callback
                                  onStop: onStopGame, // Pass stop callback
                                  onDelete: (g) => _showDeleteConfirmation(context, g), // Pass delete callback with confirmation
                                  launchState: launchState, // Pass current state
                                ),
                              );
                            },
                          ),
                          const Divider(height: 24, thickness: 1, indent: 16, endIndent: 16), // Separator between prefixes
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  int _calculateCrossAxisCount(double width, CoverSize coverSize) {
    switch (coverSize) {
      case CoverSize.small:
        if (width > 1400) return 8;
        if (width > 1200) return 7;
        if (width > 900) return 6;
        if (width > 600) return 5;
        if (width > 400) return 4;
        return 3;
      case CoverSize.medium:
        if (width > 1200) return 6;
        if (width > 900) return 5;
        if (width > 600) return 4;
        if (width > 400) return 3;
        return 2;
      case CoverSize.large:
        if (width > 1400) return 5;
        if (width > 1200) return 4;
        if (width > 900) return 3;
        if (width > 600) return 2;
        return 1;
    }
  }

  double _getAspectRatio(CoverSize coverSize) {
    switch (coverSize) {
      case CoverSize.small:
        return 0.7;
      case CoverSize.medium:
        return 0.8;
      case CoverSize.large:
        return 0.9;
    }
  }

  // Method to add executable to a specific prefix - uses the same UIActionService method
  // that's used in the prefix management screen
  void _addExecutableToPrefix(BuildContext context, WinePrefix prefix) {
    // Find uiActionService from the context
    final uiActionService = Provider.of<UIActionService>(context, listen: false);
    
    // Make sure we're using the primary navigator context for dialogs
    final navigatorContext = Navigator.of(context).context;
    
    // Use the navigator's root context for showing dialogs
    uiActionService.addExecutableToPrefix(navigatorContext, prefix);
  }

  void _showGameInfo(BuildContext context, GameEntry game) {
    showDialog(
      context: context,
      builder: (context) => GameInfoModal(
        game: game,
        onLaunchGame: () => onLaunchGame(game.prefix, game.exe),
        onUpdateMetadata: onUpdateMetadata,
      ),
    );
  }

  void _showGameSettings(BuildContext context, GameEntry game) {
    showDialog(
      context: context,
      builder: (context) => GameSettingsModal(
        game: game,
        onSaveLaunchOptions: onSaveLaunchOptions,
        onChangeCategory: onChangeCategory,
        onToggleWorkingStatus: onToggleWorkingStatus,
        onDelete: onDelete,
        onUpdateCompressedGame: onUpdateCompressedGame,
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, GameEntry game) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${game.exe.isCompressed ? 'Compressed ' : ''}Game'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${game.exe.name}"?'),
            const SizedBox(height: 8),
            Text(
              game.exe.isCompressed 
                ? 'This will remove the game from your library. The original archive file will not be deleted.'
                : 'This will remove the game from your library. The game files on disk will not be deleted.',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close confirmation dialog
              if (onDelete != null) {
                onDelete!(game);
              }
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
}
