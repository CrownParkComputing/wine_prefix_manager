import 'dart:io'; // Import dart:io for File class
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart'; // Import Provider
import 'package:file_selector/file_selector.dart'; // Use official file_selector
import '../models/prefix_models.dart'; // Import the prefix models
import '../providers/prefix_provider.dart'; // Import the PrefixProvider
// import '../services/wine_component_installer.dart'; // Not directly used here
// import 'prefix_management_page.dart'; // Not directly used here
// import '../providers/window_control_provider.dart'; // No longer needed here
import 'game_library_page.dart'; // Import GameLibraryPage
import '../widgets/game_card.dart'; // Import GameCard for GameLaunchState
import '../services/ui_action_service.dart'; // Import UIActionService
import '../services/process_service.dart'; // Import ProcessService for stop logic
import '../services/log_service.dart'; // Import LogService
import '../models/settings.dart'; // Import Settings for welcome screen (though welcome screen itself is removed from here)
import '../providers/settings_provider.dart'; // Import SettingsProvider
import '../services/igdb_service.dart'; // Import IgdbService
import '../widgets/game_search_dialog.dart'; // Import GameSearchDialog
import '../models/igdb_models.dart'; // Import IgdbGame model
import '../theme/theme_provider.dart'; // Import ThemeProvider

class HomePage extends StatefulWidget {
  final Function(int)? onNavigateToTab;

  const HomePage({
    Key? key,
    this.onNavigateToTab,
  }) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WindowListener {
  String? _selectedGenre; // State for filtering
  // State map to track running games: Key = exePath, Value = PID
  final Map<String, int> _runningGamePids = {};
  // State map to track launch state: Key = exePath, Value = GameLaunchState
  final Map<String, GameLaunchState> _gameLaunchStates = {};
  // Add state for tracking refresh status
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Any other init logic...
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    // Any other dispose logic...
    super.dispose();
  }

  // --- Game Launch/Stop Callbacks ---
  // Store the game start times to calculate play time
  final Map<String, DateTime> _gameStartTimes = {};

  void _onGameProcessStart(String exePath, int pid) {
    if (mounted) {
      final now = DateTime.now();
      setState(() {
        _runningGamePids[exePath] = pid;
        _gameLaunchStates[exePath] = GameLaunchState.running;
        _gameStartTimes[exePath] = now; // Record the start time
      });
    }
  }

  void _onGameProcessExit(String exePath, int exitCode, List<String> errors) {
    if (mounted) {
      final prefixProvider =
          Provider.of<PrefixProvider>(context, listen: false);
      final startTime = _gameStartTimes[exePath];

      if (startTime != null) {
        // Calculate play time in minutes
        final playTimeMinutes = DateTime.now().difference(startTime).inMinutes;

        // Find the game entry to update
        for (var prefix in prefixProvider.prefixes) {
          final exeIndex =
              prefix.exeEntries.indexWhere((exe) => exe.path == exePath);
          if (exeIndex != -1) {
            final exe = prefix.exeEntries[exeIndex];
            // Update play time and last played
            final updatedExe = exe.copyWith(
              playTimeMinutes: (exe.playTimeMinutes ?? 0) + playTimeMinutes,
              lastPlayed: DateTime.now(),
            );
            prefixProvider.updateExecutable(prefix, updatedExe);
            break;
          }
        }

        // Remove the start time
        _gameStartTimes.remove(exePath);
      }

      setState(() {
        _runningGamePids.remove(exePath);
        _gameLaunchStates[exePath] =
            GameLaunchState.idle; // Reset state on exit
      });
    }
    // Logging is handled within UIActionService/ProcessService
  }

  Future<void> _launchGame(BuildContext context, GameEntry entry) async {
    if (_runningGamePids.containsKey(entry.exe.path)) {
      // Already running, maybe bring to front? (Not implemented)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${entry.exe.name} is already running.')),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _gameLaunchStates[entry.exe.path] = GameLaunchState.launching;
      });
    }

    final uiActionService =
        Provider.of<UIActionService>(context, listen: false);
    // Use the specific callbacks for game state updates
    await uiActionService.launchGame(
      entry,
      onProcessStart: _onGameProcessStart,
      onProcessExit: _onGameProcessExit,
    );

    // If launchGame throws an error before starting the process, reset state
    if (mounted &&
        _gameLaunchStates[entry.exe.path] == GameLaunchState.launching &&
        !_runningGamePids.containsKey(entry.exe.path)) {
      setState(() {
        _gameLaunchStates[entry.exe.path] = GameLaunchState.idle;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to launch ${entry.exe.name}. Check logs.')),
      );
    }
  }

  Future<void> _stopGame(BuildContext context, GameEntry entry) async {
    final pid = _runningGamePids[entry.exe.path];
    if (pid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${entry.exe.name} is not running.')),
      );
      // Ensure state is idle if PID is missing
      if (mounted &&
          _gameLaunchStates[entry.exe.path] != GameLaunchState.idle) {
        setState(() {
          _gameLaunchStates[entry.exe.path] = GameLaunchState.idle;
        });
      }
      return;
    }

    final processService = Provider.of<ProcessService>(context, listen: false);
    final logService = Provider.of<LogService>(context, listen: false);
    final success = await processService.killProcess(pid);

    if (success) {
      logService.log('Kill signal sent to ${entry.exe.name} (PID: $pid)');
      // State update will happen via _onGameProcessExit callback
    } else {
      logService.log(
          'Failed to send kill signal to ${entry.exe.name} (PID: $pid)',
          LogLevel.error);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to stop ${entry.exe.name}')),
        );
      }
    }
  }
  // --- End Game Launch/Stop Callbacks ---

  // --- Helper to build GameEntry list ---
  List<GameEntry> _buildGameEntries(List<WinePrefix> prefixes) {
    final List<GameEntry> entries = [];
    for (final prefix in prefixes) {
      for (final exe in prefix.exeEntries) {
        // Optionally filter here if needed (e.g., only show entries marked as 'isGame')
        // if (exe.isGame) {
        entries.add(GameEntry(prefix: prefix, exe: exe));
        // }
      }
    }
    // Optionally sort the combined list
    entries.sort(
        (a, b) => a.exe.name.toLowerCase().compareTo(b.exe.name.toLowerCase()));
    return entries;
  }

  // Flag to toggle welcome screen - REMOVED
  // bool _showWelcomeScreen = true;

  void _navigateToManagePrefixesTab() {
    // Use the callback to navigate to the Manage tab (index 1)
    if (widget.onNavigateToTab != null) {
      widget.onNavigateToTab!(1); // Index 1 is the Manage tab
    }
  }

  void _navigateToSettingsTab() {
    // Use the callback to navigate to the Settings tab (index 2)
    if (widget.onNavigateToTab != null) {
      widget.onNavigateToTab!(2); // Index 2 is the Settings tab
    }
  }

  // Add method to refresh game data
  Future<void> _refreshGames(BuildContext context) async {
    if (_isRefreshing) return; // Don't refresh if already refreshing

    setState(() {
      _isRefreshing = true;
    });

    try {
      // Get the prefix provider and force a reload
      final prefixProvider =
          Provider.of<PrefixProvider>(context, listen: false);
      await prefixProvider.loadPrefixes(forceReload: true);

      // Clear any "not working" flags for executables that now exist
      for (var prefix in prefixProvider.prefixes) {
        for (var i = 0; i < prefix.exeEntries.length; i++) {
          final exe = prefix.exeEntries[i];
          if (exe.notWorking) {
            try {
              // Check if the file now exists
              final fileExists = await File(exe.path).exists();
              if (fileExists) {
                // Update the executable to mark it as working
                final updatedExe = exe.copyWith(notWorking: false);
                await prefixProvider.updateExecutable(prefix, updatedExe);
              }
            } catch (e) {
              // Ignore file access errors and keep the current status
            }
          }
        }
      }

      // Log the refresh action
      final logService = Provider.of<LogService>(context, listen: false);
      logService.log('Game library refreshed successfully');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Game library refreshed')),
        );
      }
    } catch (e) {
      // Log any errors
      final logService = Provider.of<LogService>(context, listen: false);
      logService.log('Error refreshing game library: $e', LogLevel.error);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to refresh game library')),
        );
      }
    } finally {
      // Always reset the refreshing state
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _updateGameMetadata(BuildContext context, GameEntry game) async {
    final igdbService = Provider.of<IgdbService>(context, listen: false);
    final prefixProvider = Provider.of<PrefixProvider>(context, listen: false);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final logService = Provider.of<LogService>(context, listen: false);

    // Import the GameSearchDialog
    final searchResult = await showDialog<IgdbGame>(
      context: context,
      builder: (_) => GameSearchDialog(
        initialQuery: game.exe.name,
        onSearch: (query) async {
          try {
            final tokenData =
                await igdbService.getIgdbToken(settingsProvider.settings);
            if (tokenData == null) return {'error': 'Could not get IGDB token'};
            final games = await igdbService.searchIgdbGames(
                query, settingsProvider.settings, tokenData['token']);
            return {'games': games};
          } catch (e) {
            return {'error': 'Search failed: $e'};
          }
        },
      ),
    );

    if (searchResult != null) {
      logService.log(
          'Fetching full details for ${searchResult.name} (ID: ${searchResult.id})...');
      ExeEntry updatedExe = game.exe;

      try {
        final tokenData =
            await igdbService.getIgdbToken(settingsProvider.settings);
        if (tokenData != null && tokenData['token'] != null) {
          final token = tokenData['token'] as String;
          final coverDetails = await igdbService.fetchCoverDetails(
              searchResult.cover, settingsProvider.settings, token);
          final screenshotDetails = await igdbService.fetchScreenshotDetails(
              searchResult.screenshots, settingsProvider.settings, token);
          final videoIds = await igdbService.fetchGameVideoIds(
              searchResult.id, settingsProvider.settings, token);

          updatedExe = game.exe.copyWith(
            igdbId: searchResult.id,
            description: searchResult.summary,
            igdbCoverId: searchResult.cover,
            coverUrl: coverDetails?['url'],
            coverImageId: coverDetails?['imageId'],
            igdbScreenshotIds: searchResult.screenshots,
            screenshotUrls: screenshotDetails.map((s) => s['url']!).toList(),
            screenshotImageIds:
                screenshotDetails.map((s) => s['imageId']!).toList(),
            videoIds: videoIds,
            isGame: true,
          );
          logService.log(
              'Successfully fetched full details for ${searchResult.name}.');
        } else {
          logService.log('Could not get IGDB token to fetch full details.',
              LogLevel.warning);
          updatedExe = game.exe.copyWith(igdbId: searchResult.id);
        }
      } catch (e) {
        logService.log(
            'Error fetching full IGDB details: $e. Updating ID only.',
            LogLevel.error);
        updatedExe = game.exe.copyWith(igdbId: searchResult.id);
      }

      await prefixProvider.updateExecutable(game.prefix, updatedExe);
      logService.log('Updated metadata for ${game.exe.name} from search.');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Metadata updated for ${game.exe.name}')),
        );
      }
    }
  }

  Future<void> _deleteGame(BuildContext context, GameEntry game) async {
    try {
      final prefixProvider =
          Provider.of<PrefixProvider>(context, listen: false);
      await prefixProvider.deleteExecutable(game.prefix, game.exe);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${game.exe.name} deleted from ${game.prefix.name}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting game: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateCompressedGame(
      BuildContext context, GameEntry game, ExeEntry updatedExe) async {
    try {
      final prefixProvider =
          Provider.of<PrefixProvider>(context, listen: false);
      await prefixProvider.updateExecutable(game.prefix, updatedExe);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${updatedExe.name} settings updated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating compressed game: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get providers
    final prefixProvider = context.watch<PrefixProvider>();
    final uiActionService =
        Provider.of<UIActionService>(context, listen: false);
    final settingsProvider = context.watch<SettingsProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    // Build game list from prefixes
    final prefixes = prefixProvider.prefixes;
    final allGames = _buildGameEntries(prefixes);

    return MultiProvider(
      providers: [
        // Make UIActionService available to the GameLibraryPage
        Provider.value(value: uiActionService),
      ],
      child: GameLibraryPage(
        games: allGames,
        // Pass callback functions for the modals
        onUpdateMetadata: (game) => _updateGameMetadata(context, game),
        onSaveLaunchOptions: (game, options) async {
          final prefixProvider =
              Provider.of<PrefixProvider>(context, listen: false);
          final updatedExe = game.exe.copyWith(launchOptions: options);
          await prefixProvider.updateExecutable(game.prefix, updatedExe);
        },
        onChangeCategory: (game, category) async {
          final prefixProvider =
              Provider.of<PrefixProvider>(context, listen: false);
          final updatedExe = game.exe.copyWith(category: category);
          await prefixProvider.updateExecutable(game.prefix, updatedExe);
        },
        onToggleWorkingStatus: (game, notWorking) async {
          final prefixProvider =
              Provider.of<PrefixProvider>(context, listen: false);
          final updatedExe = game.exe.copyWith(notWorking: notWorking);
          await prefixProvider.updateExecutable(game.prefix, updatedExe);
        },
        onDelete: (game) => _deleteGame(context, game),
        onUpdateCompressedGame: (game, updatedExe) =>
            _updateCompressedGame(context, game, updatedExe),
        onLaunchGame: (prefix, exe) =>
            _launchGame(context, GameEntry(prefix: prefix, exe: exe)),
        onGenreSelected: (genre) {
          setState(() {
            _selectedGenre = genre;
          });
        },
        selectedGenre: _selectedGenre,
        coverSize: settingsProvider.settings.coverSize,
        gameLaunchStates: _gameLaunchStates,
        onStopGame: (game) => _stopGame(context, game),
        onRefresh: () => _refreshGames(context),
        isRefreshing: _isRefreshing,
        // Pass additional callbacks for the header actions
        onShowSettings: () => _showGameLibrarySettings(context),
        onToggleTheme: () => themeProvider.toggleTheme(),
        onToggleCoverSize: () => _toggleCoverSize(context, settingsProvider),
        isDarkMode: themeProvider.isDarkMode,
      ),
    );
  }

  void _toggleCoverSize(
      BuildContext context, SettingsProvider settingsProvider) async {
    final currentSize = settingsProvider.settings.coverSize;
    CoverSize newSize;

    switch (currentSize) {
      case CoverSize.small:
        newSize = CoverSize.medium;
        break;
      case CoverSize.medium:
        newSize = CoverSize.large;
        break;
      case CoverSize.large:
        newSize = CoverSize.small;
        break;
    }

    final updatedSettings =
        settingsProvider.settings.copyWith(coverSize: newSize);
    await settingsProvider.updateSettings(updatedSettings);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cover size changed to ${newSize.name}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showGameLibrarySettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _GameLibrarySettingsDialog(),
    );
  }
}

class _GameLibrarySettingsDialog extends StatefulWidget {
  @override
  State<_GameLibrarySettingsDialog> createState() =>
      _GameLibrarySettingsDialogState();
}

class _GameLibrarySettingsDialogState
    extends State<_GameLibrarySettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _gameLibraryPathController;

  CoverSize _selectedCoverSize = CoverSize.medium;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _gameLibraryPathController = TextEditingController();

    _loadSettings();
  }

  @override
  void dispose() {
    _gameLibraryPathController.dispose();
    super.dispose();
  }

  void _loadSettings() {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final settings = settingsProvider.settings;

    setState(() {
      _gameLibraryPathController.text = settings.gameLibraryPath ?? '';
      _selectedCoverSize = settings.coverSize;
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      final currentSettings = settingsProvider.settings;
      final logService = Provider.of<LogService>(context, listen: false);

      try {
        final settingsToSave = currentSettings.copyWith(
          gameLibraryPath: _gameLibraryPathController.text.trim().isEmpty
              ? null
              : _gameLibraryPathController.text.trim(),
          coverSize: _selectedCoverSize,
        );

        await settingsProvider.updateSettings(settingsToSave);
        logService.log('Game library settings updated successfully');

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 10),
                  Text('Game library settings saved successfully'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        logService.log(
            'Failed to save game library settings: $e', LogLevel.error);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 10),
                  Text('Failed to save settings: $e'),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _selectGameLibraryPath() async {
    try {
      String? selectedDirectory = await getDirectoryPath(
          initialDirectory: _gameLibraryPathController.text);

      setState(() {
        _gameLibraryPathController.text = selectedDirectory ?? '';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting directory: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Game Library Settings'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Game Library',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _gameLibraryPathController,
                  decoration: InputDecoration(
                    labelText: 'Game Library Path (optional)',
                    hintText: 'Path to your games directory',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: _selectGameLibraryPath,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Cover Art Size',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<CoverSize>(
                  value: _selectedCoverSize,
                  decoration: const InputDecoration(
                    labelText: 'Cover Size',
                  ),
                  items: CoverSize.values.map((size) {
                    return DropdownMenuItem(
                      value: size,
                      child: Text(size.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (CoverSize? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedCoverSize = newValue;
                      });
                    }
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'IGDB Integration',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                    'IGDB Client ID and Secret are now configured globally in the application.'),
                const SizedBox(height: 16),
                const Text(
                    'All IGDB API URLs are configured globally for optimal performance.'),
                const SizedBox(height: 8),
                const Text('No additional IGDB configuration is required.',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveSettings,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
