import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../widgets/common_components_dialog.dart';
import '../providers/settings_provider.dart';

class GameDetailsPage extends StatefulWidget {
  final GameEntry game;
  final Settings settings;
  final List<WinePrefix> availablePrefixes;
  final VoidCallback onLaunchGame;
  final Function(GameEntry, bool) onToggleWorkingStatus;
  final Function(GameEntry, String?) onChangeCategory;
  final Function(GameEntry) onEditExePath;
  final Function(GameEntry) onUpdateMetadata;
  final Function(GameEntry, String?) onSaveLaunchOptions;

  const GameDetailsPage({
    super.key,
    required this.game,
    required this.settings,
    required this.availablePrefixes,
    required this.onLaunchGame,
    required this.onToggleWorkingStatus,
    required this.onChangeCategory,
    required this.onEditExePath,
    required this.onUpdateMetadata,
    required this.onSaveLaunchOptions,
  });

  @override
  State<GameDetailsPage> createState() => _GameDetailsPageState();
}

class _GameDetailsPageState extends State<GameDetailsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedCategory;
  late TextEditingController _launchOptionsController;
  final PageController _screenshotPageController = PageController();
  int _currentScreenshotIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _selectedCategory = widget.game.exe.category;
    _launchOptionsController = TextEditingController(text: widget.game.exe.launchOptions ?? '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectedCategory = widget.game.exe.category;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _launchOptionsController.dispose();
    _screenshotPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.game.exe.name),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline), text: 'Info'),
            Tab(icon: Icon(Icons.settings_outlined), text: 'Settings'),
            Tab(icon: Icon(Icons.image_outlined), text: 'Media'),
            Tab(icon: Icon(Icons.history_outlined), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInfoTab(),
          _buildSettingsTab(),
          _buildMediaTab(),
          _buildHistoryTab(),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.onLaunchGame,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Launch Game'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
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
          // Cover image
          Center(
            child: Container(
              height: 300,
              width: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildCoverImage(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Game info cards
          _buildInfoCard('Game Information', [
            _buildInfoRow('Name', widget.game.exe.name),
            _buildInfoRow('Path', widget.game.exe.path),
            _buildInfoRow('Prefix', widget.game.prefix.name),
            _buildInfoRow('Architecture', widget.game.prefix.architecture),
            _buildInfoRow('Category', widget.game.exe.category ?? 'Uncategorized'),
            if (widget.game.exe.playTimeMinutes != null && widget.game.exe.playTimeMinutes! > 0)
              _buildInfoRow('Play Time', _formatPlayTime(widget.game.exe.playTimeMinutes!)),
          ]),
          
          const SizedBox(height: 16),
          
          if (widget.game.exe.description != null && widget.game.exe.description!.isNotEmpty)
            _buildInfoCard('Description', [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  widget.game.exe.description!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard('Launch Options', [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _launchOptionsController,
                decoration: const InputDecoration(
                  labelText: 'Launch Options',
                  hintText: 'Additional command line arguments',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                onChanged: (value) {
                  widget.onSaveLaunchOptions(widget.game, value.isEmpty ? null : value);
                },
              ),
            ),
          ]),
          
          const SizedBox(height: 16),
          
          _buildInfoCard('Category', [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Consumer<SettingsProvider>(
                builder: (context, settingsProvider, child) {
                  final categories = settingsProvider.settings.categories;
                  return DropdownButtonFormField<String?>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Uncategorized'),
                      ),
                      ...categories.map((category) => DropdownMenuItem<String?>(
                        value: category,
                        child: Text(category),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value;
                      });
                      widget.onChangeCategory(widget.game, value);
                    },
                  );
                },
              ),
            ),
          ]),
          
          const SizedBox(height: 16),
          
          _buildInfoCard('Status', [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: SwitchListTile(
                title: const Text('Game is working'),
                subtitle: Text(widget.game.exe.notWorking 
                    ? 'Marked as not working' 
                    : 'Marked as working'),
                value: !widget.game.exe.notWorking,
                onChanged: (value) {
                  widget.onToggleWorkingStatus(widget.game, !value);
                },
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildMediaTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover image section
          _buildInfoCard('Cover Image', [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildCoverImage(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => widget.onUpdateMetadata(widget.game),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Update Metadata'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ]),
          
          const SizedBox(height: 16),
          
          // Screenshots section (if available)
          if (widget.game.exe.screenshotUrls.isNotEmpty)
            _buildInfoCard('Screenshots', [
              SizedBox(
                height: 200,
                child: PageView.builder(
                  controller: _screenshotPageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentScreenshotIndex = index;
                    });
                  },
                  itemCount: widget.game.exe.screenshotUrls.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          widget.game.exe.screenshotUrls[index],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.broken_image, size: 50),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.game.exe.screenshotUrls.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.game.exe.screenshotUrls.length,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _currentScreenshotIndex
                              ? Theme.of(context).primaryColor
                              : Colors.grey[400],
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard('Game History', [
            if (widget.game.exe.lastPlayed != null)
              _buildInfoRow('Last Played', DateFormat('MMM dd, yyyy HH:mm').format(widget.game.exe.lastPlayed!))
            else
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('Game has not been played yet'),
              ),
            if (widget.game.exe.playTimeMinutes != null && widget.game.exe.playTimeMinutes! > 0)
              _buildInfoRow('Total Play Time', _formatPlayTime(widget.game.exe.playTimeMinutes!)),
          ]),
        ],
      ),
    );
  }

  Widget _buildCoverImage() {
    if (widget.game.exe.localCoverPath != null && widget.game.exe.localCoverPath!.isNotEmpty) {
      return Image.file(
        File(widget.game.exe.localCoverPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackCover(),
      );
    } else if (widget.game.exe.coverUrl != null && widget.game.exe.coverUrl!.isNotEmpty) {
      return Image.network(
        widget.game.exe.coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackCover(),
      );
    } else {
      return _buildFallbackCover();
    }
  }

  Widget _buildFallbackCover() {
    return Container(
      color: Colors.grey[800],
      child: Center(
        child: Text(
          widget.game.exe.name.length >= 2
              ? widget.game.exe.name.substring(0, 2).toUpperCase()
              : widget.game.exe.name.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPlayTime(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      if (remainingMinutes == 0) {
        return '${hours}h';
      } else {
        return '${hours}h ${remainingMinutes}m';
      }
    }
  }
} 