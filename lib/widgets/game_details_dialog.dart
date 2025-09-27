import 'dart:io';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // No longer needed for Steam ID
// Removed url_launcher import as we're using Process.run instead
import 'package:intl/intl.dart'; // For date formatting
import 'package:provider/provider.dart'; // Import Provider
import '../models/prefix_models.dart';
import '../models/settings.dart';
// import '../providers/prefix_provider.dart'; // No longer needed for dynamic categories
import '../widgets/common_components_dialog.dart'; // Import for confirmation dialog
import '../providers/settings_provider.dart'; // Add SettingsProvider import

class GameDetailsDialog extends StatefulWidget {
  final GameEntry game;
  Settings settings; // Remove final to make it mutable
  final List<WinePrefix>
      availablePrefixes; // Keep for prefix change dropdown if needed later
  final VoidCallback onLaunchGame;
  final Function(GameEntry, bool) onToggleWorkingStatus;
  final Function(GameEntry, String?) onChangeCategory;
  final Function(GameEntry) onEditExePath;
  final Function(GameEntry)
      onUpdateMetadata; // New callback for metadata update
  final Function(GameEntry, String?)
      onSaveLaunchOptions; // Callback for launch options

  // Remove const since settings is now mutable
  GameDetailsDialog({
    Key? key,
    required this.game,
    required this.settings,
    required this.availablePrefixes,
    required this.onLaunchGame,
    required this.onToggleWorkingStatus,
    required this.onChangeCategory,
    required this.onEditExePath,
    required this.onUpdateMetadata,
    required this.onSaveLaunchOptions,
  }) : super(key: key);

  @override
  State<GameDetailsDialog> createState() => _GameDetailsDialogState();
}

class _GameDetailsDialogState extends State<GameDetailsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedCategory;
  late TextEditingController
      _launchOptionsController; // Controller for launch options
  // late TextEditingController _steamAppIdController; // Removed
  final PageController _screenshotPageController =
      PageController(); // Controller for screenshot carousel
  int _currentScreenshotIndex = 0; // Index for screenshot carousel

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChange); // Use separate handler
    _selectedCategory = widget.game.exe.category;
    _launchOptionsController =
        TextEditingController(text: widget.game.exe.launchOptions ?? '');
    // _steamAppIdController = TextEditingController(text: widget.game.exe.steamAppId?.toString() ?? ''); // Removed
    // _loadDynamicCategories(); // Removed dynamic category loading
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This ensures we're using the latest settings when the dialog shows
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Update selected category to match current game's category
      _selectedCategory = widget.game.exe.category;

      // Get fresh settings with latest categories
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      widget.settings = settingsProvider.settings;
      setState(() {}); // Trigger a rebuild to refresh categories
    });
  }

  // Removed _loadDynamicCategories method

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange); // Remove listener
    _tabController.dispose();
    _launchOptionsController.dispose();
    // _steamAppIdController.dispose(); // Removed
    _screenshotPageController.dispose(); // Dispose screenshot controller
    super.dispose();
  }

  // Add a handler for tab changes if needed elsewhere, ensure listener removal
  void _handleTabChange() {
    if (mounted && _tabController.indexIsChanging) {
      // Optional: Handle index changing if needed
    } else if (mounted && !_tabController.indexIsChanging) {
      // Optional: Handle index change completion if needed
    }
  }

  @override
  Widget build(BuildContext context) {
    // Removed explicit width/height calculations
    // final double dialogWidth = MediaQuery.of(context).size.width * 0.8;
    // final double dialogHeight = MediaQuery.of(context).size.height * 0.9;

    return Dialog(
      // Make dialog fill the screen
      insetPadding: EdgeInsets.zero,
      // Remove rounded corners for full screen
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        // Remove explicit width/height to allow filling
        // width: dialogWidth,
        // height: dialogHeight,
        padding: EdgeInsets.zero,
        child: Column(
          // Keep MainAxisSize.min if content might not fill screen,
          // or use MainAxisSize.max if it should always stretch.
          // Let's try max first for full screen effect.
          mainAxisSize: MainAxisSize.max,
          children: [
            // Custom header with close button
            Container(
              padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 8), // Adjust padding slightly
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                // Remove top radius for full screen
                // borderRadius: const BorderRadius.only(
                //   topLeft: Radius.circular(16),
                //   topRight: Radius.circular(16),
                // ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.game.exe.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis, // Prevent overflow
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close Details',
                  ),
                ],
              ),
            ),

            // Tab Bar - Modified to show only icons
            Container(
              color: Theme.of(context).primaryColor.withOpacity(0.8),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white, // Make indicator visible
                tabs: const [
                  Tab(
                      icon: Tooltip(
                          message: 'Info', child: Icon(Icons.info_outline))),
                  Tab(
                      icon: Tooltip(
                          message: 'Settings',
                          child: Icon(Icons.settings_outlined))),
                  Tab(
                      icon: Tooltip(
                          message: 'Media', child: Icon(Icons.image_outlined))),
                  Tab(
                      icon: Tooltip(
                          message: 'History',
                          child: Icon(Icons.history_outlined))),
                ],
              ),
            ),

            // Tab content - Ensure it expands
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildInfoTab(),
                  _buildSettingsTab(),
                  _buildMediaTab(),
                  _buildHistoryTab(),
                ],
              ),
            ),

            // Action buttons - Keep at bottom
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                    onPressed: widget.onLaunchGame,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Game cover/banner image
          if (widget.game.exe.localCoverPath != null &&
              widget.game.exe.localCoverPath!.isNotEmpty)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.file(
                  File(widget.game.exe.localCoverPath!),
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image, size: 100),
                ),
              ),
            )
          else if (widget.game.exe.coverUrl != null &&
              widget.game.exe.coverUrl!.isNotEmpty)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.network(
                  widget.game.exe.coverUrl!,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image, size: 100),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()));
                  },
                ),
              ),
            )
          else
            const Center(
                child: Icon(Icons.image_not_supported,
                    size: 100, color: Colors.grey)),

          const SizedBox(height: 20),

          // Game Description
          if (widget.game.exe.description != null &&
              widget.game.exe.description!.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Description',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(widget.game.exe.description!),
                const SizedBox(height: 20),
              ],
            ),

          // Basic game info
          Text('Game Information',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _buildInfoRow(
              'Status', widget.game.exe.notWorking ? 'Not Working' : 'Working'),
          _buildInfoRow(
              'Category', widget.game.exe.category ?? 'Uncategorized'),
          _buildInfoRow('Prefix', widget.game.prefix.name),
          _buildInfoRow('Prefix Type',
              widget.game.prefix.type.toString().split('.').last),
          _buildInfoRow('Executable', widget.game.exe.path),
          // if (widget.game.exe.steamAppId != null) // Removed Steam App ID display
          //   _buildInfoRow('Steam App ID', widget.game.exe.steamAppId.toString()),
          if (widget.game.exe.launchOptions != null &&
              widget.game.exe.launchOptions!.isNotEmpty)
            _buildInfoRow('Launch Options', widget.game.exe.launchOptions!),
          // Show play time information
          _buildInfoRow('Play Time',
              _formatPlayTime(widget.game.exe.playTimeMinutes ?? 0)),
          if (widget.game.exe.lastPlayed != null)
            _buildInfoRow(
                'Last Played', _formatDate(widget.game.exe.lastPlayed!)),
          if (widget.game.exe.igdbId != null)
            _buildInfoRow('IGDB ID', widget.game.exe.igdbId.toString()),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    // Get the latest categories from settings
    // Add null for 'Uncategorized' and ensure we have the latest categories
    final List<String?> availableCategories = [
      null,
      ...widget.settings.categories
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Game Status Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Game Status',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Mark as Not Working'),
                    subtitle:
                        const Text('Toggle if the game has issues running'),
                    value: widget.game.exe.notWorking,
                    onChanged: (value) =>
                        widget.onToggleWorkingStatus(widget.game, value),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Category Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Category',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  DropdownButton<String?>(
                    value: _selectedCategory,
                    isExpanded: true,
                    hint: const Text('Select Category'),
                    items: availableCategories
                        .map((String? category) => DropdownMenuItem<String?>(
                              value: category,
                              child: Text(category ?? 'Uncategorized'),
                            ))
                        .toList(),
                    onChanged: (String? newValue) {
                      setState(() => _selectedCategory = newValue);
                      widget.onChangeCategory(widget.game, _selectedCategory);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Category saved'),
                            duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Executable Path Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Executable Settings',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.edit_note),
                    title: const Text('Edit Executable Path'),
                    subtitle: Text(widget.game.exe.path,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => widget.onEditExePath(widget.game),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Steam App ID Section (Removed)
          // Card(...)

          // const SizedBox(height: 16), // Removed spacer

          // Launch Options Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Launch Options',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Enter environment variables (e.g., VAR=value) or command-line arguments, separated by spaces.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _launchOptionsController,
                    decoration: const InputDecoration(
                      hintText: 'e.g., SteamDeck=0 %command% -arg',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: null,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      final options = _launchOptionsController.text.trim();
                      widget.onSaveLaunchOptions(
                          widget.game, options.isEmpty ? null : options);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Launch options saved'),
                            duration: Duration(seconds: 1)),
                      );
                    },
                    child: const Text('Save Launch Options'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Metadata Settings Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Metadata Settings',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.manage_search),
                    title: const Text('Update Game Metadata'),
                    subtitle: Text(widget.game.exe.igdbId != null
                        ? 'Fetch latest details from IGDB (ID: ${widget.game.exe.igdbId})'
                        : 'Search IGDB and fetch details'),
                    onTap: () => widget.onUpdateMetadata(widget.game),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaTab() {
    final screenshots = [
      if (widget.game.exe.localScreenshotPaths.isNotEmpty)
        ...widget.game.exe.localScreenshotPaths
            .map((path) => {'type': 'local', 'path': path}),
      if (widget.game.exe.screenshotUrls.isNotEmpty)
        ...widget.game.exe.screenshotUrls
            .map((url) => {'type': 'network', 'path': url}),
    ];

    final videos = widget.game.exe.videoIds;

    return SingleChildScrollView(
      // Keep SingleChildScrollView for overall tab scrolling
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screenshots Section - Replaced GridView with PageView
          Text('Screenshots', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (screenshots.isEmpty)
            const Center(child: Text('No screenshots available.'))
          else
            Column(
              // Wrap PageView and indicators in a Column
              children: [
                SizedBox(
                  height: 200, // Define a height for the carousel
                  child: PageView.builder(
                    controller: _screenshotPageController,
                    itemCount: screenshots.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentScreenshotIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final screenshot = screenshots[index];
                      final isLocal = screenshot['type'] == 'local';
                      final path = screenshot['path'];
                      return Padding(
                        // Add padding around each image
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: GestureDetector(
                          onTap: () => _showImageCarousel(context, screenshots,
                              index), // Keep full screen view on tap
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.0),
                            child: isLocal
                                ? (path != null
                                    ? Image.file(File(path),
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.broken_image))
                                    : const Icon(Icons.broken_image))
                                : (path != null
                                    ? Image.network(path,
                                        fit: BoxFit.contain,
                                        loadingBuilder:
                                            (context, child, loadingProgress) {
                                          if (loadingProgress == null) {
                                            return child;
                                          }
                                          return const Center(
                                              child:
                                                  CircularProgressIndicator());
                                        },
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.broken_image))
                                    : const Icon(Icons.broken_image)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Optional: Add page indicators
                if (screenshots.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(screenshots.length, (index) {
                      return Container(
                        width: 8.0,
                        height: 8.0,
                        margin: const EdgeInsets.symmetric(
                            vertical: 10.0, horizontal: 2.0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentScreenshotIndex == index
                              ? Theme.of(context).primaryColor
                              : Colors.grey.withOpacity(0.5),
                        ),
                      );
                    }),
                  ),
              ],
            ),

          const SizedBox(height: 24),

          // Videos Section
          Text('Videos', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (videos.isEmpty)
            const Text('No videos available.')
          else
            ListView.builder(
              shrinkWrap: true,
              physics:
                  const NeverScrollableScrollPhysics(), // Disable ListView scrolling
              itemCount: videos.length,
              itemBuilder: (context, index) {
                final videoId = videos[index];
                final thumbnailUrl =
                    'https://img.youtube.com/vi/$videoId/0.jpg';
                final videoUrl = 'https://www.youtube.com/watch?v=$videoId';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Image.network(thumbnailUrl,
                        width: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.video_library)),
                    title: Text('Video ${index + 1}'),
                    subtitle: Text(videoUrl),
                    trailing: const Icon(Icons.play_circle_outline),
                    onTap: () => _launchVideoUrl(videoUrl),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Game play time card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Play Time',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),

                  // Total play time
                  _buildInfoRow('Total Play Time',
                      _formatPlayTime(widget.game.exe.playTimeMinutes ?? 0)),

                  // Last played time
                  if (widget.game.exe.lastPlayed != null)
                    _buildInfoRow('Last Played',
                        _formatDate(widget.game.exe.lastPlayed!)),

                  // No play time detected message
                  if ((widget.game.exe.playTimeMinutes ?? 0) == 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Play time tracking will begin when you next launch this game.',
                        style: TextStyle(
                            fontStyle: FontStyle.italic, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Launch history (placeholder for future implementation)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Launch History',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  // Future implementation: List of game launches with dates/times
                  const Text(
                      'Detailed launch history will be available in a future update.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // Helper to show image carousel dialog (remains for full-screen view)
  void _showImageCarousel(BuildContext context,
      List<Map<String, String>> images, int initialIndex) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        // Use StatefulBuilder to manage the index within the dialog
        int currentIndex = initialIndex;
        final PageController pageController =
            PageController(initialPage: initialIndex);

        return StatefulBuilder(
          builder: (stfContext, stfSetState) {
            return Dialog(
              backgroundColor: Colors.black.withOpacity(0.8),
              insetPadding: EdgeInsets.zero, // Full screen
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PageView.builder(
                    controller: pageController,
                    itemCount: images.length,
                    onPageChanged: (index) {
                      stfSetState(() {
                        currentIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final image = images[index];
                      final isLocal = image['type'] == 'local';
                      final path = image['path']!;
                      return InteractiveViewer(
                        // Allow zooming
                        child: isLocal
                            ? Image.file(File(path), fit: BoxFit.contain)
                            : Image.network(
                                path,
                                fit: BoxFit.contain,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(
                                      child: CircularProgressIndicator(
                                          color: Colors.white));
                                },
                                errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image,
                                        color: Colors.white, size: 50)),
                              ),
                      );
                    },
                  ),
                  // Close button
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 30),
                      onPressed: () => Navigator.of(stfContext).pop(),
                    ),
                  ),
                  // Left navigation arrow
                  if (currentIndex > 0)
                    Positioned(
                      left: 10,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios,
                            color: Colors.white, size: 30),
                        onPressed: () {
                          pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut);
                        },
                      ),
                    ),
                  // Right navigation arrow
                  if (currentIndex < images.length - 1)
                    Positioned(
                      right: 10,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_forward_ios,
                            color: Colors.white, size: 30),
                        onPressed: () {
                          pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut);
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Helper to show video URL
  Future<void> _launchVideoUrl(String url) async {
    try {
      // On Linux, we'll just show the URL in a snackbar for the user to copy
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Video URL (copy to browser):'),
                const SizedBox(height: 4),
                Text(
                  url,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }

      // Try to use xdg-open as a fallback
      try {
        await Process.run('xdg-open', [url]);
      } catch (e) {
        // Silently fail if xdg-open doesn't work
        // We've already shown the URL in the snackbar
      }
    } catch (e) {
      // Handle error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open video: $e')),
        );
      }
    }
  }

  // Helper method to format play time
  String _formatPlayTime(int minutes) {
    if (minutes < 60) {
      return '$minutes minutes';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return '$hours hour${hours != 1 ? 's' : ''} $remainingMinutes minute${remainingMinutes != 1 ? 's' : ''}';
    }
  }

  // Helper method to format date
  String _formatDate(DateTime date) {
    return DateFormat('MMM d, y - h:mm a').format(date);
  }
}
