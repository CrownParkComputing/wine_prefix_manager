import 'dart:io';
import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../widgets/game_card.dart';
import '../pages/home_page.dart'; // Import for ViewMode enum

class GameCarouselPage extends StatefulWidget {
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

  const GameCarouselPage({
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
    this.currentViewMode = ViewMode.carousel,
    this.isDarkMode = false,
  });

  @override
  State<GameCarouselPage> createState() => _GameCarouselPageState();
}

class _GameCarouselPageState extends State<GameCarouselPage> {
  PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.8);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Apply genre filter first
    final filteredGames = widget.selectedGenre != null
        ? widget.games.where((game) => game.exe.category == widget.selectedGenre).toList()
        : widget.games;

    if (filteredGames.isEmpty) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: _buildEmptyState(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Game counter and navigation
          _buildGameCounter(filteredGames),
          
          // Main carousel
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemCount: filteredGames.length,
              itemBuilder: (context, index) {
                final game = filteredGames[index];
                final launchState = widget.gameLaunchStates[game.exe.path] ?? GameLaunchState.idle;
                return _buildGameCarouselItem(context, game, launchState, index == _currentIndex);
              },
            ),
          ),
          
          // Bottom controls
          _buildBottomControls(filteredGames),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: const Text(
        'Game Gallery',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        // View mode toggle button (always shown)
        IconButton(
          icon: Icon(
            widget.currentViewMode == ViewMode.grid
                ? Icons.grid_view
                : widget.currentViewMode == ViewMode.list
                    ? Icons.view_list
                    : Icons.view_carousel,
            color: Colors.white,
          ),
          tooltip: 'Switch View (${widget.currentViewMode.name})',
          onPressed: widget.onToggleViewMode,
        ),
        // Theme toggle button (always shown)
        IconButton(
          icon: Icon(
            widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            color: Colors.white,
          ),
          onPressed: widget.onToggleTheme,
        ),
        // Settings button (always shown)
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          onPressed: widget.onShowSettings,
        ),
        // Refresh button (always shown)
        IconButton(
          icon: widget.isRefreshing 
            ? const SizedBox(
                width: 24, 
                height: 24, 
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                )
              ) 
            : const Icon(Icons.refresh, color: Colors.white),
          tooltip: 'Refresh Game Library',
          onPressed: widget.isRefreshing ? null : widget.onRefresh,
        ),
      ],
    );
  }

  Widget _buildGameCounter(List<GameEntry> games) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_currentIndex + 1} of ${games.length}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
          if (widget.selectedGenre != null)
            Chip(
              label: Text('Category: ${widget.selectedGenre!}'),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () {
                if (widget.onGenreSelected != null) {
                  widget.onGenreSelected!(null);
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildGameCarouselItem(BuildContext context, GameEntry game, GameLaunchState launchState, bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: EdgeInsets.symmetric(
        horizontal: isActive ? 8 : 16,
        vertical: isActive ? 20 : 40,
      ),
      child: Card(
        elevation: isActive ? 12 : 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.grey.shade900,
                Colors.black,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Small cover image on the left
                SizedBox(
                  width: 160,
                  child: Column(
                    children: [
                      _buildSmallGameCover(game),
                      const SizedBox(height: 16),
                      _buildActionButtons(context, game, launchState),
                    ],
                  ),
                ),
                
                const SizedBox(width: 20),
                
                // Game information on the right
                Expanded(
                  child: _buildDetailedGameInfo(context, game, launchState),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallGameCover(GameEntry game) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
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
          width: double.infinity,
          height: double.infinity,
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
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey.shade800,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Loading cover...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
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
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.withOpacity(0.8),
            Colors.purple.withOpacity(0.8),
            Colors.indigo.withOpacity(0.8),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              game.exe.isGame ? Icons.sports_esports : Icons.apps,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              game.exe.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedGameInfo(BuildContext context, GameEntry game, GameLaunchState launchState) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Game title and launch status
          Row(
            children: [
              Expanded(
                child: Text(
                  game.exe.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildLaunchStateIndicator(launchState),
            ],
          ),
          const SizedBox(height: 16),
          
          // Game description/summary
          if (game.exe.description != null && game.exe.description!.isNotEmpty) ...[
            const Text(
              'Description',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                game.exe.description!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          
          // Game details
          _buildCompactGameDetails(context, game),
          const SizedBox(height: 20),
          
          // Screenshots section
          if (game.exe.screenshotImageIds.isNotEmpty) ...[
            const Text(
              'Screenshots',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildScreenshotsGrid(game.exe.screenshotImageIds),
            const SizedBox(height: 20),
          ],
          
          // Technical details
          _buildTechnicalDetails(game),
        ],
      ),
    );
  }

  Widget _buildCompactGameDetails(BuildContext context, GameEntry game) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Game Information',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          // Wrap details in a grid for better space usage
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              // Category
              if (game.exe.category != null && game.exe.category!.isNotEmpty)
                _buildCompactDetailItem(
                  icon: Icons.category,
                  title: 'Category',
                  value: game.exe.category!,
                ),
              
              // IGDB ID if available
              if (game.exe.igdbId != null)
                _buildCompactDetailItem(
                  icon: Icons.games,
                  title: 'IGDB ID',
                  value: game.exe.igdbId.toString(),
                ),
              
              // Steam App ID if available
              if (game.exe.steamAppId != null)
                _buildCompactDetailItem(
                  icon: Icons.videogame_asset,
                  title: 'Steam App ID',
                  value: game.exe.steamAppId.toString(),
                ),
              
              // Play time if available
              if (game.exe.playTimeMinutes != null && game.exe.playTimeMinutes! > 0)
                _buildCompactDetailItem(
                  icon: Icons.access_time,
                  title: 'Play Time',
                  value: _formatPlayTime(game.exe.playTimeMinutes!),
                ),
              
              // Last played
              if (game.exe.lastPlayed != null)
                _buildCompactDetailItem(
                  icon: Icons.history,
                  title: 'Last Played',
                  value: _formatDateTime(game.exe.lastPlayed!),
                ),
              
              // Status indicators
              if (game.exe.notWorking)
                _buildCompactDetailItem(
                  icon: Icons.warning,
                  title: 'Status',
                  value: 'Not Working',
                  valueColor: Colors.orange,
                ),
              
              if (game.exe.isCompressed)
                _buildCompactDetailItem(
                  icon: Icons.archive,
                  title: 'Type',
                  value: 'Compressed Game',
                  valueColor: Colors.blue,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDetailItem({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return SizedBox(
      width: 180,
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.white70,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotsGrid(List<String> screenshotImageIds) {
    if (screenshotImageIds.isEmpty) return const SizedBox.shrink();
    
    return SizedBox(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: screenshotImageIds.length,
        itemBuilder: (context, index) {
          final imageId = screenshotImageIds[index];
          final screenshotUrl = 'https://images.igdb.com/igdb/image/upload/t_screenshot_med/$imageId.jpg';
          
          return Container(
            width: 200,
            margin: const EdgeInsets.only(right: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: GestureDetector(
                onTap: () => _showFullScreenshot(screenshotUrl, imageId),
                child: Image.network(
                  screenshotUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: Colors.grey.shade800,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey.shade800,
                      child: const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                          size: 32,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTechnicalDetails(GameEntry game) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Technical Details',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          _buildDetailRow(
            icon: game.prefix.type == PrefixType.wine ? Icons.wine_bar : Icons.games,
            title: 'Wine Prefix',
            value: '${game.prefix.name} (${game.prefix.type == PrefixType.wine ? 'Wine' : 'Proton'})',
          ),
          
          _buildDetailRow(
            icon: Icons.folder,
            title: 'Executable Path',
            value: game.exe.path.split('/').last,
          ),
          
          if (game.exe.launchOptions != null && game.exe.launchOptions!.isNotEmpty)
            _buildDetailRow(
              icon: Icons.settings,
              title: 'Launch Options',
              value: game.exe.launchOptions!,
            ),
        ],
      ),
    );
  }

  void _showFullScreenshot(String screenshotUrl, String imageId) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                'https://images.igdb.com/igdb/image/upload/t_screenshot_big/$imageId.jpg',
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.black87,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.black87,
                    child: const Center(
                      child: Text(
                        'Failed to load screenshot',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.white70,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: Text(
              '$title:',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLaunchStateIndicator(GameLaunchState launchState) {
    switch (launchState) {
      case GameLaunchState.launching:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
      case GameLaunchState.running:
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.play_arrow,
            color: Colors.white,
            size: 16,
          ),
        );
      case GameLaunchState.failed:
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.error,
            color: Colors.white,
            size: 16,
          ),
        );
      default:
        return const SizedBox(width: 20, height: 20);
    }
  }

  Widget _buildActionButtons(BuildContext context, GameEntry game, GameLaunchState launchState) {
    return _buildLaunchButton(context, game, launchState);
  }

  Widget _buildLaunchButton(BuildContext context, GameEntry game, GameLaunchState launchState) {
    switch (launchState) {
      case GameLaunchState.running:
        return Container(
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IconButton(
            onPressed: () => widget.onStopGame(game),
            icon: const Icon(Icons.stop, color: Colors.white, size: 28),
            tooltip: 'Stop Game',
            padding: const EdgeInsets.all(12),
          ),
        );
      case GameLaunchState.launching:
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
          ),
        );
      default:
        return Container(
          decoration: BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IconButton(
            onPressed: () => widget.onLaunchGame(game.prefix, game.exe),
            icon: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
            tooltip: 'Launch Game',
            padding: const EdgeInsets.all(12),
          ),
        );
    }
  }

  Widget _buildBottomControls(List<GameEntry> games) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous button
          IconButton(
            onPressed: _currentIndex > 0
                ? () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                : null,
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
          ),
          
          // Page indicators
          Row(
            children: List.generate(
              games.length > 10 ? 10 : games.length,
              (index) {
                final actualIndex = games.length > 10 
                    ? ((_currentIndex / games.length) * 10).round() + index - 5
                    : index;
                
                if (actualIndex < 0 || actualIndex >= games.length) {
                  return const SizedBox.shrink();
                }
                
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: actualIndex == _currentIndex ? 12 : 8,
                  height: actualIndex == _currentIndex ? 12 : 8,
                  decoration: BoxDecoration(
                    color: actualIndex == _currentIndex 
                        ? Colors.white 
                        : Colors.white38,
                    shape: BoxShape.circle,
                  ),
                );
              },
            ),
          ),
          
          // Next button
          IconButton(
            onPressed: _currentIndex < games.length - 1
                ? () {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                : null,
            icon: const Icon(Icons.chevron_right, color: Colors.white, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.sports_esports_outlined,
            size: 80,
            color: Colors.white54,
          ),
          const SizedBox(height: 24),
          Text(
            widget.selectedGenre != null
                ? 'No games found in category "${widget.selectedGenre}"'
                : 'No games found in library',
            style: const TextStyle(
              fontSize: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Add games via the Manage tab',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPlayTime(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 30) {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else {
      return 'Recently';
    }
  }
}