import 'dart:io';
import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../widgets/game_card.dart'; // Import GameCard for GameLaunchState
import '../pages/home_page.dart'; // Import for ViewMode enum

class GameListViewPage extends StatelessWidget {
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
  final Map<String, GameLaunchState> gameLaunchStates;
  final Function(GameEntry) onStopGame;
  final VoidCallback? onRefresh;
  final bool isRefreshing;
  final VoidCallback? onShowSettings;
  final VoidCallback? onToggleTheme;
  final VoidCallback? onToggleViewMode;
  final ViewMode currentViewMode;
  final bool isDarkMode;

  const GameListViewPage({
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
    required this.gameLaunchStates,
    required this.onStopGame,
    this.onRefresh,
    this.isRefreshing = false,
    this.onShowSettings,
    this.onToggleTheme,
    this.onToggleViewMode,
    this.currentViewMode = ViewMode.list,
    this.isDarkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // Apply genre filter first
    final filteredGames = selectedGenre != null
        ? games.where((game) => game.exe.category == selectedGenre).toList()
        : games;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game List'),
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
            tooltip: isDarkMode ? 'Light Mode' : 'Dark Mode',
            onPressed: onToggleTheme,
          ),
          // Settings button (always shown)
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
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
            tooltip: 'Refresh',
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
                ? Center(
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
                : ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: filteredGames.length,
                    itemBuilder: (context, index) {
                      final game = filteredGames[index];
                      final launchState = gameLaunchStates[game.exe.path] ?? GameLaunchState.idle;
                      
                      return _buildGameListItem(context, game, launchState);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameListItem(BuildContext context, GameEntry game, GameLaunchState launchState) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Game Cover/Icon
            _buildGameCover(game),
            const SizedBox(width: 16),
            
            // Game Information
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Game Name and Status
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          game.exe.name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _buildLaunchStateIndicator(launchState),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Game Details
                  _buildGameDetails(context, game),
                  
                  const SizedBox(height: 12),
                  
                  // Action Buttons
                  Row(
                    children: [
                      _buildLaunchButton(context, game, launchState),
                      const SizedBox(width: 8),
                      _buildInfoButton(context, game),
                      const SizedBox(width: 8),
                      _buildSettingsButton(context, game),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameCover(GameEntry game) {
    return Container(
      width: 120,
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _buildCoverImage(game),
      ),
    );
  }

  Widget _buildCoverImage(GameEntry game) {
    // Check for custom cover art first
    final customCoverPath = game.exe.localCoverPath;
    if (customCoverPath != null && customCoverPath.isNotEmpty) {
      final customCoverFile = File(customCoverPath);
      if (customCoverFile.existsSync()) {
        return Image.file(
          customCoverFile,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildFallbackCover(game),
        );
      }
    }

    // Check for IGDB cover art
    final igdbCoverUrl = game.exe.coverUrl;
    if (igdbCoverUrl != null && igdbCoverUrl.isNotEmpty) {
      return Image.network(
        igdbCoverUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildFallbackCover(game),
      );
    }

    return _buildFallbackCover(game);
  }

  Widget _buildFallbackCover(GameEntry game) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.withValues(alpha: 0.7),
            Colors.purple.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              game.exe.isGame ? Icons.sports_esports : Icons.apps,
              size: 40,
              color: Colors.white,
            ),
            const SizedBox(height: 8),
            Text(
              game.exe.name.substring(0, game.exe.name.length > 10 ? 10 : game.exe.name.length),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLaunchStateIndicator(GameLaunchState launchState) {
    switch (launchState) {
      case GameLaunchState.launching:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case GameLaunchState.running:
        return Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.play_arrow,
            color: Colors.white,
            size: 12,
          ),
        );
      case GameLaunchState.failed:
        return Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.error,
            color: Colors.white,
            size: 12,
          ),
        );
      default:
        return const SizedBox(width: 16, height: 16);
    }
  }

  Widget _buildGameDetails(BuildContext context, GameEntry game) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Prefix Information
        Row(
          children: [
            Icon(
              game.prefix.type == PrefixType.wine ? Icons.wine_bar : Icons.games,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${game.prefix.name} • ${game.prefix.type == PrefixType.wine ? 'Wine' : 'Proton'}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        
        // Path Information
        Row(
          children: [
            const Icon(Icons.folder_outlined, size: 16, color: Colors.grey),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                game.exe.path,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        
        // Category if available
        if (game.exe.category != null && game.exe.category!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.category_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Chip(
                label: Text(
                  game.exe.category!,
                  style: const TextStyle(fontSize: 12),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
        
        // Working status indicator
        if (game.exe.notWorking) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.warning_outlined, size: 16, color: Colors.orange),
              const SizedBox(width: 4),
              Text(
                'Not Working',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ],
        
        // Compressed game indicator
        if (game.exe.isCompressed) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.archive_outlined, size: 16, color: Colors.blue),
              const SizedBox(width: 4),
              Text(
                'Compressed Game',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLaunchButton(BuildContext context, GameEntry game, GameLaunchState launchState) {
    switch (launchState) {
      case GameLaunchState.running:
        return ElevatedButton.icon(
          onPressed: () => onStopGame(game),
          icon: const Icon(Icons.stop, size: 16),
          label: const Text('Stop'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
        );
      case GameLaunchState.launching:
        return ElevatedButton.icon(
          onPressed: null,
          icon: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: const Text('Launching...'),
        );
      default:
        return ElevatedButton.icon(
          onPressed: () => onLaunchGame(game.prefix, game.exe),
          icon: const Icon(Icons.play_arrow, size: 16),
          label: const Text('Launch'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
        );
    }
  }

  Widget _buildInfoButton(BuildContext context, GameEntry game) {
    return OutlinedButton.icon(
      onPressed: () => _showGameInfo(context, game),
      icon: const Icon(Icons.info_outline, size: 16),
      label: const Text('Info'),
    );
  }

  Widget _buildSettingsButton(BuildContext context, GameEntry game) {
    return OutlinedButton.icon(
      onPressed: () => _showGameSettings(context, game),
      icon: const Icon(Icons.settings_outlined, size: 16),
      label: const Text('Settings'),
    );
  }

  void _showGameInfo(BuildContext context, GameEntry game) {
    if (onUpdateMetadata != null) {
      onUpdateMetadata!(game);
    }
  }

  void _showGameSettings(BuildContext context, GameEntry game) {
    // This would typically show a settings dialog
    // For now, just call the category change callback as an example
  }
}