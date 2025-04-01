import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart';

class GameDetailsDialog extends StatefulWidget {
  final GameEntry game;
  final Settings settings;
  final List<WinePrefix> availablePrefixes;
  final VoidCallback onLaunchGame;
  final Function(GameEntry) onEditGame;
  final Function(GameEntry) onChangePrefix;
  final Function(GameEntry) onMoveGameFolder;
  final Function(GameEntry, bool) onToggleWorkingStatus;
  final Function(GameEntry, String?) onChangeCategory;
  final Function(GameEntry) onEditExePath; // New callback for editing exe path

  const GameDetailsDialog({
    Key? key,
    required this.game,
    required this.settings,
    required this.availablePrefixes,
    required this.onLaunchGame,
    required this.onEditGame,
    required this.onChangePrefix,
    required this.onMoveGameFolder,
    required this.onToggleWorkingStatus,
    required this.onChangeCategory,
    required this.onEditExePath, // Add required parameter
  }) : super(key: key);

  @override
  State<GameDetailsDialog> createState() => _GameDetailsDialogState();
}

class _GameDetailsDialogState extends State<GameDetailsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedCategory;
  int _currentTabIndex = 0;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      }
    });
    _selectedCategory = widget.game.exe.category;
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double dialogWidth = MediaQuery.of(context).size.width * 0.8;
    final double dialogHeight = MediaQuery.of(context).size.height * 0.8;
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Custom header with close button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
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
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            // Tab Bar (outside of AppBar for better layout)
            Container(
              color: Theme.of(context).primaryColor.withOpacity(0.8),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: const [
                  Tab(icon: Icon(Icons.info), text: 'Info'),
                  Tab(icon: Icon(Icons.settings), text: 'Settings'),
                  Tab(icon: Icon(Icons.image), text: 'Media'),
                  Tab(icon: Icon(Icons.history), text: 'History'),
                ],
              ),
            ),
            
            // Tab content with explicit constraints
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
            
            // Action buttons at the bottom
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                    onPressed: widget.onLaunchGame,
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Details'),
                    onPressed: () {
                      widget.onEditGame(widget.game);
                      Navigator.pop(context);
                    },
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
          if (widget.game.exe.localCoverPath != null && widget.game.exe.localCoverPath!.isNotEmpty)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.file(
                  File(widget.game.exe.localCoverPath!),
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            )
          else if (widget.game.exe.coverUrl != null && widget.game.exe.coverUrl!.isNotEmpty)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.network(
                  widget.game.exe.coverUrl!,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          
          const SizedBox(height: 20),
          
          // Game Description
          if (widget.game.exe.description != null && widget.game.exe.description!.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Description',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(widget.game.exe.description!),
                const SizedBox(height: 20),
              ],
            ),
          
          // Basic game info
          Text(
            'Game Information',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          _buildInfoRow('Status', widget.game.exe.notWorking ? 'Not Working' : 'Working'),
          _buildInfoRow('Category', widget.game.exe.category ?? 'Uncategorized'),
          _buildInfoRow('Prefix', widget.game.prefix.name),
          _buildInfoRow('Prefix Type', widget.game.prefix.type.toString().split('.').last),
          _buildInfoRow('Executable', widget.game.exe.path),
          if (widget.game.exe.igdbId != null)
            _buildInfoRow('IGDB ID', widget.game.exe.igdbId.toString()),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    // Define a predefined list of categories
    final List<String> predefinedCategories = [
      'Action', 
      'Adventure', 
      'RPG', 
      'Strategy', 
      'Simulation', 
      'Sports', 
      'Racing', 
      'Puzzle', 
      'Other'
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
                  Text('Game Status', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Mark as Not Working'),
                    subtitle: const Text('Toggle if the game has issues running'),
                    value: widget.game.exe.notWorking,
                    onChanged: (value) {
                      widget.onToggleWorkingStatus(widget.game, value);
                      Navigator.pop(context); // Close dialog after change
                    },
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
                  Text('Category', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  // Radio buttons for category selection
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Uncategorized option
                      RadioListTile<String?>(
                        title: const Text('Uncategorized'),
                        value: null,
                        groupValue: _selectedCategory,
                        onChanged: (value) {
                          setState(() {
                            _selectedCategory = value;
                          });
                        },
                      ),
                      // Generate a radio tile for each predefined category
                      ...predefinedCategories.map((category) => 
                        RadioListTile<String>(
                          title: Text(category),
                          value: category,
                          groupValue: _selectedCategory,
                          onChanged: (value) {
                            setState(() {
                              _selectedCategory = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      widget.onChangeCategory(widget.game, _selectedCategory);
                      Navigator.pop(context); // Close dialog after change
                    },
                    child: const Text('Save Category'),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // New Executable Path Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Executable Settings', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.edit_note),
                    title: const Text('Edit Executable Path'),
                    subtitle: Text(
                      widget.game.exe.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      widget.onEditExePath(widget.game);
                      Navigator.pop(context); // Close dialog after action
                    },
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Prefix Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Prefix Settings', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.folder_special),
                    title: const Text('Change Prefix'),
                    subtitle: Text('Current: ${widget.game.prefix.name}'),
                    onTap: () {
                      widget.onChangePrefix(widget.game);
                      Navigator.pop(context); // Close dialog after action
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_copy),
                    title: const Text('Move Game Folder'),
                    subtitle: const Text('Relocate the game installation'),
                    onTap: () {
                      widget.onMoveGameFolder(widget.game);
                      Navigator.pop(context); // Close dialog after action
                    },
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screenshots Section
          if (widget.game.exe.localScreenshotPaths.isNotEmpty || 
              widget.game.exe.screenshotUrls.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Screenshots',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.game.exe.localScreenshotPaths.isNotEmpty
                        ? widget.game.exe.localScreenshotPaths.length
                        : widget.game.exe.screenshotUrls.length,
                    itemBuilder: (context, index) {
                      final bool isLocal = widget.game.exe.localScreenshotPaths.isNotEmpty;
                      final String imagePath = isLocal 
                          ? widget.game.exe.localScreenshotPaths[index]
                          : widget.game.exe.screenshotUrls[index];
                      
                      return Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: isLocal
                              ? Image.file(
                                  File(imagePath),
                                  fit: BoxFit.cover,
                                  width: 300,
                                  errorBuilder: (context, error, stackTrace) {
                                    // Remove print statement for better error handling
                                    return Container(
                                      width: 300,
                                      color: Colors.grey[800],
                                      child: const Center(
                                        child: Icon(Icons.broken_image, size: 50, color: Colors.white70),
                                      ),
                                    );
                                  },
                                )
                              : Image.network(
                                  imagePath, // Using direct URL without base URL prefix
                                  fit: BoxFit.cover,
                                  width: 300,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      width: 300,
                                      color: Colors.grey[800],
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 300,
                                      color: Colors.grey[800],
                                      child: const Center(
                                        child: Icon(Icons.broken_image, size: 50, color: Colors.white70),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          
          // Videos Section
          if (widget.game.exe.videoIds.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Videos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                // Add note about YouTube videos
                const Padding(
                  padding: EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    'Note: Videos open in your browser. YouTube thumbnails are displayed below.',
                    style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                  ),
                ),
                Column(
                  children: widget.game.exe.videoIds.map((videoId) {
                    final videoUrl = 'https://www.youtube.com/watch?v=$videoId';
                    final thumbnailUrl = 'https://img.youtube.com/vi/$videoId/0.jpg';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Video thumbnail with play button overlay
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              // YouTube thumbnail
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                child: Image.network(
                                  thumbnailUrl,
                                  width: double.infinity,
                                  height: 180,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: double.infinity,
                                    height: 180,
                                    color: Colors.grey[800],
                                    child: const Icon(Icons.video_library, size: 50, color: Colors.white70),
                                  ),
                                ),
                              ),
                              // Play button overlay
                              IconButton(
                                icon: const Icon(
                                  Icons.play_circle_outline,
                                  size: 60,
                                  color: Colors.white,
                                ),
                                onPressed: () => _launchUrl(videoUrl),
                              ),
                            ],
                          ),
                          // Video title and link
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const Icon(Icons.videogame_asset),
                                const SizedBox(width: 8),
                                const Expanded(child: Text('Game Trailer')),
                                IconButton(
                                  icon: const Icon(Icons.open_in_new),
                                  onPressed: () => _launchUrl(videoUrl),
                                  tooltip: 'Open in browser',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          
          // IGDB Link
          if (widget.game.exe.igdbId != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(
                  'External Links',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('View on IGDB'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchUrl('https://www.igdb.com/games/${widget.game.exe.igdbId}'),
                ),
              ],
            ),
        ],
      ),
    );
  }
  
  Widget _buildHistoryTab() {
    // Placeholder for game history - could track play time, achievements, etc.
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Play history and statistics coming soon',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  void _launchUrl(String url) async {
    try {
      if (await canLaunch(url)) {
        await launch(url);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch $url: $e')),
      );
    }
  }
}