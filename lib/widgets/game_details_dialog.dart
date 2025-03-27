import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/prefix_models.dart'; // Import only from prefix_models.dart
import '../models/settings.dart';

class GameDetailsDialog extends StatefulWidget {
  final GameEntry game;
  final Settings settings;
  final List<WinePrefix> availablePrefixes;
  final Function(GameEntry) onEditGame;
  final Function(GameEntry) onChangePrefix;
  final Function() onLaunchGame;
  final Function(GameEntry, bool) onToggleWorkingStatus;
  final Function(GameEntry, String?) onChangeCategory;
  final Function(GameEntry) onMoveGameFolder; // Add this line

  const GameDetailsDialog({
    Key? key,
    required this.game,
    required this.settings,
    required this.availablePrefixes,
    required this.onEditGame,
    required this.onChangePrefix,
    required this.onLaunchGame,
    required this.onToggleWorkingStatus,
    required this.onChangeCategory,
    required this.onMoveGameFolder, // Ensure this is required
  }) : super(key: key);

  @override
  State<GameDetailsDialog> createState() => _GameDetailsDialogState();
}

class _GameDetailsDialogState extends State<GameDetailsDialog> {
  // Add a page controller as a class field
  late PageController _screenshotController;
  int _currentScreenshotIndex = 0;
  
  @override
  void initState() {
    super.initState();
    _screenshotController = PageController();
  }
  
  @override
  void dispose() {
    _screenshotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGameInfo(),
                      const SizedBox(height: 16),
                      _buildActionButtons(),
                      const SizedBox(height: 24),
                      if (widget.game.exe.description != null)
                        _buildDescription(),
                      const SizedBox(height: 16),
                      _buildScreenshots(),
                      const SizedBox(height: 16),
                      if (widget.game.exe.videoIds.isNotEmpty)
                        _buildVideoLinks(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AppBar(
      title: Text(widget.game.exe.name),
      actions: [
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildGameInfo() {
    final color = widget.game.exe.notWorking ? Colors.red : Colors.green;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Prefix Selection
            Row(
              children: [
                const Text('Prefix: '),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<WinePrefix>(
                    value: widget.game.prefix,
                    isExpanded: true,
                    items: widget.availablePrefixes.map((prefix) {
                      return DropdownMenuItem<WinePrefix>(
                        value: prefix,
                        child: Text(
                          prefix.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (prefix) {
                      if (prefix != null && prefix != widget.game.prefix) {
                        Navigator.pop(context); // Close the dialog first
                        widget.onChangePrefix(widget.game);
                      }
                    },
                  ),
                ),
              ],
            ),
            const Divider(),
            
            // Category Selection
            Row(
              children: [
                const Text('Category: '),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: widget.game.exe.category,
                  hint: const Text('Uncategorized'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Uncategorized'),
                    ),
                    ...widget.settings.categories.map((String category) {
                      return DropdownMenuItem<String?>(
                        value: category,
                        child: Text(category),
                      );
                    }),
                  ],
                  onChanged: (String? category) {
                    widget.onChangeCategory(widget.game, category);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            const Divider(),
            
            // Working Status
            Row(
              children: [
                const Text('Status: '),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    widget.game.exe.notWorking ? 'Not Working' : 'Working',
                    style: TextStyle(color: color),
                  ),
                  backgroundColor: color.withOpacity(0.1),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    widget.onToggleWorkingStatus(widget.game, !widget.game.exe.notWorking);
                    Navigator.pop(context);
                  },
                  child: Text(
                    widget.game.exe.notWorking ? 'Mark as Working' : 'Mark as Not Working'
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: const Text('Play'),
          onPressed: () {
            Navigator.pop(context);
            widget.onLaunchGame();
          },
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.edit),
          label: const Text('Edit Details'),
          onPressed: () {
            Navigator.pop(context);
            widget.onEditGame(widget.game);
          },
        ),
        ElevatedButton.icon( // Add this button
          icon: const Icon(Icons.drive_file_move_outline),
          label: const Text('Move Folder'),
          onPressed: () {
            Navigator.pop(context);
            widget.onMoveGameFolder(widget.game);
          },
        ),
      ],
    );
  }

  Widget _buildDescription() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Description',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(widget.game.exe.description ?? ''),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenshots() {
    if (widget.game.exe.screenshotUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Screenshots',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            SizedBox(
              height: 220,
              child: PageView.builder(
                controller: _screenshotController,
                itemCount: widget.game.exe.screenshotUrls.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentScreenshotIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => _showFullScreenImage(widget.game.exe.screenshotUrls[index]),
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 4.0),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(
                        widget.game.exe.screenshotUrls[index],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade300,
                          child: const Center(child: Icon(Icons.broken_image, size: 48)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // Left/Right navigation arrows
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left arrow
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                    ),
                    onPressed: _currentScreenshotIndex > 0
                        ? () {
                            _screenshotController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        : null,
                  ),
                  
                  // Right arrow
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
                    ),
                    onPressed: _currentScreenshotIndex < widget.game.exe.screenshotUrls.length - 1
                        ? () {
                            _screenshotController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Indicator dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.game.exe.screenshotUrls.length,
            (index) => Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index == _currentScreenshotIndex
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoLinks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Videos',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.game.exe.videoIds.map((videoId) {
            final index = widget.game.exe.videoIds.indexOf(videoId) + 1;
            return ElevatedButton.icon(
              icon: const Icon(Icons.play_circle_outline),
              label: Text('Video $index'),
              onPressed: () => _launchYouTubeVideo(videoId),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _launchYouTubeVideo(String videoId) async {
    final url = Uri.parse('https://www.youtube.com/watch?v=$videoId');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open video')),
        );
      }
    }
  }

  void _showFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(child: Icon(Icons.broken_image, size: 64));
                },
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
