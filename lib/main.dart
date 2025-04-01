import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'dart:async'; // For StreamSubscription
import 'package:connectivity_plus/connectivity_plus.dart'; // For connectivity check
import 'package:provider/provider.dart';
import 'models/wine_build.dart';
import 'models/settings.dart';
import 'models/prefix_models.dart'; // Import only from prefix_models.dart
import 'models/igdb_models.dart';
import 'pages/settings_page.dart';
import 'widgets/game_search_dialog.dart';
// import 'widgets/game_card.dart'; // No longer directly used here
import 'widgets/game_details_dialog.dart';
import 'theme/theme_provider.dart';
// import 'widgets/game_carousel.dart'; // No longer directly used here
import 'pages/game_library_page.dart';
import 'pages/prefix_management_page.dart'; // Import the new page
import 'pages/prefix_creation_page.dart'; // Import the new page
import 'services/build_service.dart'; // Import BuildService
import 'services/igdb_service.dart'; // Import IgdbService
// import 'services/prefix_storage_service.dart'; // Moved to Provider
import 'services/process_service.dart'; // Import ProcessService
import 'services/prefix_creation_service.dart'; // Import PrefixCreationService
// import 'services/prefix_management_service.dart'; // Moved to Provider
import 'services/cover_art_service.dart'; // Import CoverArtService (still needed for _addExeToPrefix flow)
import 'package:window_manager/window_manager.dart'; // Import window_manager
import 'widgets/custom_title_bar.dart' as custom_window_buttons; // Import the custom title bar buttons with a prefix
import 'providers/prefix_provider.dart'; // Import the new provider
import 'package:bitsdojo_window/bitsdojo_window.dart'; // Add this for better window management
import 'pages/home_page.dart';
import 'services/log_service.dart';
import 'pages/logs_page.dart';
import 'widgets/window_buttons.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Log Service
  final logService = LogService();
  await logService.initialize();
  
  // Initialize windowManager for window controls
  await windowManager.ensureInitialized();
  
  // Configure windowManager
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  
  // Replace with simpler initialization for bitsdojo_window
  // This helps avoid mouse tracker conflicts
  doWhenWindowReady(() {
    const initialSize = Size(1200, 800);
    appWindow.minSize = const Size(800, 600);
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.title = "Wine Prefix Manager";
    appWindow.show();
  });
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => PrefixProvider()), // Add PrefixProvider
      ],
      child: const WinePrefixManager(),
    ),
  );
}

class WinePrefixManager extends StatelessWidget {
  const WinePrefixManager({super.key});

  @override
  Widget build(BuildContext context) {
    // ThemeProvider is still accessed directly here for the MaterialApp theme
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Wine Prefix Manager',
      theme: themeProvider.themeData,
      // Remove the Stack and use a direct HomePage
      home: const HomePage(),
      debugShowCheckedModeBanner: false, // Remove debug banner
    );
  }
}

// Remove the WindowBorder class completely as it's causing issues

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // List<BaseBuild> _builds = []; // Removed, managed by PrefixCreationPage
  // List<WinePrefix> _prefixes = []; // Removed, managed by PrefixProvider
  final Map<String, int> _runningProcesses = {}; // Keep local for UI tracking
  // BaseBuild? _selectedBuild; // Removed
  // PrefixType _selectedPrefixType = PrefixType.wine; // Removed
  bool _isLoading = false; // Keep local for UI operations not in provider (e.g., process start/stop, IGDB fetch)
  // String _prefixName = ''; // Removed
  String _status = ''; // Keep local for UI feedback (non-prefix related)
  Settings? _settings;
  // final TextEditingController _prefixNameController = TextEditingController(); // Removed
  int _currentTabIndex = 0;
  String? _selectedGenre;
  // int _initialTabIndex = 2; // Removed, using _currentTabIndex

  // Connectivity state
  bool _isConnected = true; // Assume connected initially
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // Service instances (Remove services moved to provider)
  final BuildService _buildService = BuildService();
  final IgdbService _igdbService = IgdbService();
  // final PrefixStorageService _prefixStorageService = PrefixStorageService(); // Removed
  final ProcessService _processService = ProcessService();
  final PrefixCreationService _prefixCreationService = PrefixCreationService();
  // final PrefixManagementService _prefixManagementService = PrefixManagementService(); // Removed
  final CoverArtService _coverArtService = CoverArtService(); // Keep for now (used in _addExeToPrefix)

  // Access provider instance
  late PrefixProvider _prefixProvider; // Declare provider instance variable

  // Remove the _logMessages list since we're using LogService now
  final LogService _logService = LogService();
  
  // Replace _addLogMessage with this method that uses LogService
  void _addLogMessage(String message, [LogLevel level = LogLevel.info]) {
    _logService.log(message, level);
  }

  @override
  void initState() {
    super.initState();
    // Get provider instance - listen: false because we don't need to rebuild HomePage when provider changes
    // We'll use context.watch or Consumer where needed in the build method.
    _prefixProvider = Provider.of<PrefixProvider>(context, listen: false);
    _initialize();
    _initConnectivity(); // Check initial status
    // Listen for changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
    
    // Add initial log message
    _addLogMessage('Application started');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel(); // Cancel subscription
    // _prefixNameController.dispose(); // Removed
    super.dispose();
  }

  // Helper method to check initial connectivity
  Future<void> _initConnectivity() async {
    late ConnectivityResult result;
    try {
      result = await Connectivity().checkConnectivity();
    } catch (e) {
      print('Error checking connectivity: $e');
      _updateConnectionStatus(ConnectivityResult.none); // Assume offline on error
      return;
    }
    // Update status once after initial check
    return _updateConnectionStatus(result);
  }

  // Helper method to update connection status state
  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    final isConnected = result != ConnectivityResult.none;
    if (_isConnected != isConnected) { // Only update state if it changed
      setState(() {
        _isConnected = isConnected;
        _status = _isConnected ? 'Online' : 'Offline'; // Update status message
      });
      if (_isConnected) {
        // If we just came online, check for missing images
        _prefixProvider.checkAndDownloadMissingImages();
      }
      print('Connectivity changed: ${_isConnected ? "Online" : "Offline"}');
    }
  }

  Future<void> _initialize() async {
      debugPrint("[_initialize] Settings loaded. Image Base URL: ${_settings?.igdbImageBaseUrl}"); // Log loaded value

    await _loadSettings();
    if (_settings != null) {
       // Update provider with settings *before* loading/scanning
      _prefixProvider.updateSettings(_settings!);
      // Trigger provider actions
      _prefixProvider.loadPrefixes();
      _prefixProvider.scanForPrefixes();
    }
    // _fetchBuilds(); // Removed, handled by PrefixCreationPage
  }

  Future<void> _loadSettings() async {
    _settings = await AppSettings.load();
    // Update local state if needed, provider is updated in _initialize
    setState(() {});
  }

  // Future<void> _fetchBuilds() async { ... } // Removed, handled by PrefixCreationPage

  // /// Scans for existing prefixes using PrefixManagementService and merges with current list.
  // Future<void> _scanForPrefixes() async { ... } // Removed, handled by provider

  // /// Saves the current list of prefixes using PrefixStorageService.
  // Future<void> _savePrefixes() async { ... } // Removed, handled by provider

  /// Runs an executable using the ProcessService.
  Future<void> _runExe(WinePrefix prefix, ExeEntry exe) async {
    // Check if already running
    if (_runningProcesses.containsKey(exe.path)) {
      setState(() {
        _status = '${exe.name} is already running (PID: ${_runningProcesses[exe.path]})';
      });
      _addLogMessage('${exe.name} is already running (PID: ${_runningProcesses[exe.path]})');
      return;
    }

    setState(() {
      _isLoading = true; // Set loading true when starting
      _status = 'Starting ${exe.name}...';
    });
    _addLogMessage('Starting ${exe.name}...');

    await _processService.runExecutable(
      prefix,
      exe,
      onProcessStart: (startedExePath, pid) {
        // Ensure updates happen on the UI thread
        if (mounted) {
          setState(() {
            _runningProcesses[startedExePath] = pid;
            _status = 'Running ${exe.name} (PID: $pid)';
            // Keep isLoading true while running
          });
          _addLogMessage('Running ${exe.name} (PID: $pid)');
        }
      },
      onProcessExit: (exitedExePath, exitCode, errors) async { // Add async here
         // Ensure updates happen on the UI thread
        if (mounted) {
          setState(() {
            _runningProcesses.remove(exitedExePath);
            if (exitCode != 0) {
               _status = 'Error running ${exe.name} (Code: $exitCode): ${errors.join('\n')}';
               _addLogMessage('Error running ${exe.name} (Code: $exitCode): ${errors.join('\n')}');
            } else {
               _status = '${exe.name} exited successfully (Code: $exitCode)';
               _addLogMessage('${exe.name} exited successfully (Code: $exitCode)');
            }
            _isLoading = false; // Set loading false when process exits or fails to start
          });
          // Removed windowManager.focus() and windowManager.show() calls
        }
      },
    );
    // Note: If runExecutable returns null (failed to start), the onProcessExit callback
    // is called immediately by the service, which will set isLoading = false.
  }

  /// Kills a running process using the ProcessService.
  Future<void> _killProcess(WinePrefix prefix, ExeEntry exe) async {
    final pid = _runningProcesses[exe.path];
    if (pid == null) {
      setState(() {
        _status = '${exe.name} is not running.';
      });
      _addLogMessage('${exe.name} is not running.');
      return;
    }

    setState(() {
      _status = 'Attempting to kill ${exe.name} (PID: $pid)...';
    });
    _addLogMessage('Attempting to kill ${exe.name} (PID: $pid)...');

    final success = await _processService.killProcess(pid);

    // ProcessService's runExecutable onProcessExit callback handles removing
    // the process from _runningProcesses and updating status upon successful termination.
    // We only need to update status here if the kill command itself failed.
    if (!success && mounted) { // Check mounted after async gap
       setState(() {
         _status = 'Failed to issue kill command for ${exe.name} (PID: $pid). It might still be running.';
         // We don't remove from _runningProcesses here, as the process might still exit normally
       });
       _addLogMessage('Failed to issue kill command for ${exe.name} (PID: $pid). It might still be running.');
    } else if (success && mounted) {
       // Optional: Update status immediately if kill command succeeded,
       // but the onProcessExit callback provides more definitive confirmation.
       _addLogMessage('Kill command sent for ${exe.name} (PID: $pid).');
    }
  }

  /// Deletes an executable entry from a prefix using the Provider.
  Future<void> _deleteExecutable(WinePrefix prefix, ExeEntry exeToDelete) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text('Are you sure you want to delete the executable "${exeToDelete.name}" from the prefix "${prefix.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) { // Check mounted after async gap
      // Call provider to delete
      await _prefixProvider.deleteExecutable(prefix, exeToDelete);
      // Update local status based on provider status (optional, provider might handle it)
      setState(() { _status = _prefixProvider.status; });
       // If the deleted exe was running, remove it from local tracking map
      if (_runningProcesses.containsKey(exeToDelete.path)) {
        setState(() {
           _runningProcesses.remove(exeToDelete.path);
        });
        print('Removed deleted executable from running process tracking.');
      }
    } else {
       if (mounted) {
         setState(() { _status = 'Executable deletion cancelled.'; });
       }
    }
  }

  /// Runs Winetricks for the specified prefix in a new terminal window.
  Future<void> _runWinetricks(WinePrefix prefix) async {
    if (!Platform.isLinux) {
       if (mounted) {
         setState(() { _status = 'Winetricks can only be run on Linux.'; });
       }
       return;
    }

    // Check if winetricks command exists
    final checkResult = await Process.run('which', ['winetricks']);
    if (checkResult.exitCode != 0) {
       if (mounted) {
         setState(() { _status = 'Error: "winetricks" command not found. Please install Winetricks.'; });
       }
       return;
    }
     // Check if terminal emulator exists (try gnome-terminal first)
    final termCheckResult = await Process.run('which', ['gnome-terminal']);
    String terminalCommand = 'gnome-terminal';
    if (termCheckResult.exitCode != 0) {
        // Try konsole as a fallback
        final konsoleCheck = await Process.run('which', ['konsole']);
        if (konsoleCheck.exitCode == 0) {
            terminalCommand = 'konsole';
        } else {
             // Try xterm as a last resort
            final xtermCheck = await Process.run('which', ['xterm']);
             if (xtermCheck.exitCode == 0) {
                 terminalCommand = 'xterm';
             } else {
                if (mounted) {
                    setState(() { _status = 'Error: No supported terminal emulator found (gnome-terminal, konsole, xterm).'; });
                }
                return;
             }
        }
    }


    setState(() {
      _status = 'Launching Winetricks for prefix "${prefix.name}"...';
    });

    // Construct the command to run Winetricks within the chosen terminal
    // Use sh -c to handle environment variables and the actual command properly
    final command = terminalCommand;
    final args = [
        if (terminalCommand == 'konsole' || terminalCommand == 'xterm') '-e', // Argument for konsole/xterm to execute command
        if (terminalCommand == 'gnome-terminal') '--', // Argument separator for gnome-terminal
        'sh', // Use shell to handle env var and command
        '-c',
        'WINEPREFIX="${prefix.path}" winetricks; echo "Winetricks closed. Press Enter to exit terminal."; read' // Run winetricks, keep terminal open
    ];


    try {
      // Run the terminal command, but don't wait for it to finish
      final process = await Process.start(command, args, runInShell: false); // Don't run the terminal itself in a shell

      // Optional: Check if the process started successfully (exitCode is only available after exit)
      // We can't easily track the Winetricks GUI process itself this way.
      print('Launched terminal process (PID: ${process.pid}) for Winetricks.');
       if (mounted) {
         setState(() { _status = 'Winetricks launched for "${prefix.name}". Check the new terminal window.'; });
       }

    } catch (e) {
      print('Error launching Winetricks: $e');
       if (mounted) {
         setState(() {
           _status = 'Error launching Winetricks: $e';
         });
       }
    }
  }


  // /// Loads prefixes using PrefixStorageService.
  // Future<void> _loadPrefixes() async { ... } // Removed, handled by provider

  // Future<void> _downloadAndCreatePrefix() async { ... } // Removed, handled by PrefixCreationPage

  /// Adds an executable to a prefix after potentially fetching game details.
  Future<void> _addExeToPrefix(WinePrefix prefix) async {
    String? filePath;
    ExeEntry? newExeEntry; // Use nullable type

    setState(() { _isLoading = true; _status = 'Selecting executable...'; });

    try {
      // 1. Pick Exe File
      filePath = await _pickExeFile();
      if (filePath == null) {
         setState(() { _isLoading = false; _status = 'Executable selection cancelled.'; });
         return; // User cancelled
      }

      // 2. Ask if Game
      final isGame = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog( /* ... Game/App Dialog ... */
           title: const Text('Game or Application?'),
           content: const Text('Is this a game or a regular application?'),
           actions: [
             TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Application')),
             TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Game')),
           ],
        ),
      );
      if (isGame == null) {
        setState(() { _isLoading = false; _status = 'Executable type selection cancelled.'; });
        return; // User cancelled
      }

      // 3. Create Base ExeEntry or Fetch Game Details
      if (isGame && _settings?.igdbClientId?.isNotEmpty == true) {
        final filename = path.basenameWithoutExtension(filePath);
        setState(() { _status = 'Searching IGDB for "$filename"...'; });

        final game = await showDialog<IgdbGame>(
          context: context,
          builder: (context) => GameSearchDialog(
            initialQuery: filename,
            onSearch: _searchIgdbGames,
          ),
        );

        if (game != null) {
          setState(() { _status = 'Fetching game details...'; });
          final tokenResult = await _getIgdbToken();
          if (tokenResult.containsKey('error')) {
            setState(() { _status = 'Error getting IGDB token: ${tokenResult['error']}'; });
            // Create entry without details as fallback
            newExeEntry = ExeEntry(path: filePath, name: game.name, igdbId: game.id, isGame: true);
          } else {
            final String token = tokenResult['token'];
            // Fetch details (cover, screenshots, videos) including image IDs
            final coverDetails = await _fetchCoverDetails(game.cover, token); // Renamed method call
            final screenshotDetails = await _fetchScreenshotDetails(game.screenshots, token); // Renamed method call
            final videoIds = await _fetchGameVideoIds(game.id, token);

            final String? coverUrl = coverDetails?['url'];
            final String? coverImageId = coverDetails?['imageId'];
            final List<String> screenshotUrls = screenshotDetails.map((s) => s['url']!).toList();
            final List<String> screenshotImageIds = screenshotDetails.map((s) => s['imageId']!).toList();

            String? localCoverPath;
            List<String> localScreenshotPaths = [];

            if (game.id != null && coverUrl != null) {
              setState(() { _status = 'Downloading cover art...'; });
              // Pass the URL to the cover art service
              localCoverPath = await _coverArtService.getLocalCoverPath(game.id!, coverUrl);
            }
            if (screenshotUrls.isNotEmpty) {
               setState(() { _status = 'Downloading screenshots...'; });
               // Pass the URLs to the cover art service
               localScreenshotPaths = await _coverArtService.getLocalScreenshotPaths(screenshotUrls);
            }

            newExeEntry = ExeEntry(
              path: filePath,
              name: game.name,
              igdbId: game.id,
              coverUrl: coverUrl,
              coverImageId: coverImageId, // Store image ID
              localCoverPath: localCoverPath,
              screenshotUrls: screenshotUrls,
              screenshotImageIds: screenshotImageIds, // Store image IDs
              localScreenshotPaths: localScreenshotPaths,
              videoIds: videoIds,
              isGame: true,
              description: game.summary,
            );
             _printExeEntryInfo(newExeEntry!); // Log details
             setState(() { _status = 'Game details fetched.'; });
          }
        } else {
           // User cancelled IGDB search, create basic entry
           newExeEntry = ExeEntry(path: filePath, name: path.basename(filePath), isGame: true); // Still mark as game maybe? Or use isGame=false? Let's stick with true for now.
           setState(() { _status = 'IGDB search cancelled. Added basic game entry.'; });
        }
      } else {
        // Regular application or IGDB not configured/used
        newExeEntry = ExeEntry(
          path: filePath,
          name: path.basename(filePath),
          isGame: isGame,
        );
         setState(() { _status = 'Added application entry.'; });
      }

      // 4. Add to Prefix via Provider (if entry was created)
      if (newExeEntry != null) {
         await _prefixProvider.addExecutable(prefix, newExeEntry!);
         // Update local status based on provider's status
         setState(() { _status = _prefixProvider.status; });
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error adding executable: $e';
        });
      }
      print('Error in _addExeToPrefix: $e');
    } finally {
       if (mounted) {
          setState(() { _isLoading = false; });
       }
    }
  }

  /// Deletes a prefix after confirmation using the Provider.
  Future<void> _deletePrefix(WinePrefix prefix) async {
     final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete Prefix'),
        content: Text('Are you sure you want to delete the prefix "${prefix.name}" and all its contents? This action CANNOT be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('DELETE', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

     if (confirmed == true && mounted) {
        // TODO: Add actual directory deletion logic in the provider or service
        await _prefixProvider.deletePrefix(prefix);
        // Update local status
        setState(() { _status = _prefixProvider.status; });
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(_prefixProvider.status)), // Show provider status
        );
     } else {
        if (mounted) {
           setState(() { _status = 'Prefix deletion cancelled.'; });
        }
     }
  }

  // Removed _openSettings method as it's now in the main navigation
  // void _openSettings() async { ... }

  /// Retrieves a valid IGDB token using the IgdbService.
  /// Updates local settings if a new token is fetched.
  /// Returns a map containing the token or an error message.
  Future<Map<String, dynamic>> _getIgdbToken() async {
    if (_settings == null) {
      return {'error': 'Settings not loaded.'};
    }
    if (_settings!.igdbClientId.isEmpty || _settings!.igdbClientSecret.isEmpty) {
      return {'error': 'IGDB credentials not set. Configure in Settings.'};
    }

    print('Checking/Fetching IGDB token...');

    try {
      final tokenData = await _igdbService.getIgdbToken(_settings!);

      if (tokenData != null) {
        final String token = tokenData['token'];
        final DateTime expiry = tokenData['expiry'];
        final bool isNew = tokenData['isNew'];

        // If it's a newly fetched token, update the settings
        if (isNew) {
          print("Updating settings with new IGDB token.");
          // Calculate duration from now until expiry
          final expiresIn = expiry.difference(DateTime.now());
          // Use await here as updateToken is async
          // Update local _settings and save
          _settings = await AppSettings.updateToken(_settings!, token, expiresIn);
          // Also update the provider's settings instance
          _prefixProvider.updateSettings(_settings!);
          setState((){}); // Update UI if settings display depends on it
        }
        // No setState here for status update
        return {'token': token};
      } else {
        // No setState here
        return {'error': 'Failed to get IGDB token. Check credentials and network.'};
      }
    } catch (e) {
      print('Error getting IGDB token: $e');
      // No setState here
      return {'error': 'Error getting IGDB token: $e'};
    }
  }


  /// Searches IGDB for games using the IgdbService.
  /// Returns a Future that resolves to a Map containing either 'games' or 'error'.
  Future<Map<String, dynamic>> _searchIgdbGames(String query) async {
    final tokenResult = await _getIgdbToken(); // This now returns a Map

    if (tokenResult.containsKey('error')) {
      print('Cannot search IGDB: ${tokenResult['error']}');
      // Update local status to inform user
      if (mounted) setState(() => _status = 'Cannot search IGDB: ${tokenResult['error']}');
      return {'error': tokenResult['error']}; // Propagate the error
    }

    final String token = tokenResult['token'];
    if (_settings == null) {
       print('Cannot search IGDB: Settings are null.');
       if (mounted) setState(() => _status = 'Cannot search IGDB: Settings not loaded.');
       return {'error': 'Settings not loaded.'};
    }

    print('Searching IGDB for "$query"...'); // Log instead of setState
    if (mounted) setState(() => _status = 'Searching IGDB for "$query"...');
    try {
      final results = await _igdbService.searchIgdbGames(query, _settings!, token);
      print('Found ${results.length} game(s).'); // Log instead of setState
      if (mounted) setState(() => _status = 'Found ${results.length} game(s).');
      return {'games': results}; // Return games list in a map
    } catch (e) {
      print('Error searching IGDB: $e'); // Log instead of setState
      if (mounted) setState(() => _status = 'Error searching IGDB: $e');
      return {'error': 'Error searching IGDB: $e'}; // Return error in a map
    }
  }


  /// Fetches cover details (URL and image ID) for a given cover ID using the IgdbService.
  Future<Map<String, String>?> _fetchCoverDetails(int? coverId, String token) async { // Renamed and changed return type
    if (coverId == null || _settings == null) return null;

    try {
      return await _igdbService.fetchCoverDetails(coverId, _settings!, token); // Renamed service call
    } catch (e) {
      print('Error fetching cover URL in HomePage: $e');
      if (mounted) setState(() { _status = 'Error fetching cover: $e'; });
      return null;
    }
  }

  /// Fetches screenshot details (URL and image ID) for given IDs using the IgdbService.
  Future<List<Map<String, String>>> _fetchScreenshotDetails(List<int> screenshotIds, String token) async { // Renamed and changed return type
    if (screenshotIds.isEmpty || _settings == null) return [];

    try {
      return await _igdbService.fetchScreenshotDetails(screenshotIds, _settings!, token); // Renamed service call
    } catch (e) {
      print('Error fetching screenshot URLs in HomePage: $e');
      if (mounted) setState(() { _status = 'Error fetching screenshots: $e'; });
      return [];
    }
  }

  /// Fetches game video IDs for a given game ID using the IgdbService.
  Future<List<String>> _fetchGameVideoIds(int gameId, String token) async {
    if (_settings == null) return [];

    try {
      // Debug print moved to service if needed
      return await _igdbService.fetchGameVideoIds(gameId, _settings!, token);
    } catch (e) {
      print('Error fetching game video IDs in HomePage: $e');
      if (mounted) setState(() { _status = 'Error fetching videos: $e'; });
      return [];
    }
  }

  // Add this helper method to log video IDs
  void _printExeEntryInfo(ExeEntry entry) {
    print('Game: ${entry.name}');
    print('- IGDB ID: ${entry.igdbId}');
    print('- Has cover: ${entry.coverUrl != null}');
    print('- Local Cover: ${entry.localCoverPath ?? 'None'}');
    print('- Screenshots: ${entry.screenshotUrls.length}');
    print('- Local Screenshots: ${entry.localScreenshotPaths.length}');
    print('- Videos: ${entry.videoIds.length}');
    print('- Video IDs: ${entry.videoIds}');
  }

  // /// Checks loaded prefixes for missing local images and attempts download.
  // Future<void> _checkAndDownloadMissingImages() async { ... } // Removed, handled by provider

  /// Helper to pick an EXE file using FilePicker or Zenity fallback.
  Future<String?> _pickExeFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe'],
      );

      if (result != null && result.files.single.path != null) {
        return result.files.single.path!;
      }

      // Fallback to zenity if file picker didn't work
      try {
        final shell = Shell();
        final zenityResult = await shell.run(
          'zenity --file-selection --title="Select Windows Executable" --file-filter="*.exe"'
        );
        if (zenityResult.outText.isNotEmpty) {
          return zenityResult.outText.trim();
        }
      } catch (e) {
        throw Exception('Please install zenity or ensure FilePicker works');
      }
    } catch (e) {
      throw Exception('Error selecting file: $e');
    }
    return null; // User cancelled or error
  }

  /// Edits game details by re-running the IGDB search and update flow. Uses Provider.
  Future<void> _editGameDetails(GameEntry gameEntry) async {
    final filename = path.basenameWithoutExtension(gameEntry.exe.path);
    setState(() { _isLoading = true; _status = 'Searching IGDB for "$filename"...'; });

    try {
      final game = await showDialog<IgdbGame>(
        context: context,
        builder: (context) => GameSearchDialog(
          initialQuery: filename,
          onSearch: _searchIgdbGames,
        ),
      );

      if (game != null) {
        setState(() { _status = 'Updating game details...'; });
        final tokenResult = await _getIgdbToken();
        if (tokenResult.containsKey('error')) {
          throw Exception('Error getting IGDB token: ${tokenResult['error']}');
        }

        final String token = tokenResult['token'];
        // Fetch details including image IDs
        final coverDetails = await _fetchCoverDetails(game.cover, token); // Renamed method call
        final screenshotDetails = await _fetchScreenshotDetails(game.screenshots, token); // Renamed method call
        final videoIds = await _fetchGameVideoIds(game.id, token);

        final String? coverUrl = coverDetails?['url'];
        final String? coverImageId = coverDetails?['imageId'];
        final List<String> screenshotUrls = screenshotDetails.map((s) => s['url']!).toList();
        final List<String> screenshotImageIds = screenshotDetails.map((s) => s['imageId']!).toList();

        String? localCoverPath;
        List<String> localScreenshotPaths = [];

        // Download images
        if (game.id != null && coverUrl != null) {
           setState(() { _status = 'Downloading cover art...'; });
           // Pass the URL to the cover art service
           localCoverPath = await _coverArtService.getLocalCoverPath(game.id!, coverUrl);
        }
        if (screenshotUrls.isNotEmpty) {
           setState(() { _status = 'Downloading screenshots...'; });
           // Pass the URLs to the cover art service
           localScreenshotPaths = await _coverArtService.getLocalScreenshotPaths(screenshotUrls);
        }

        // Create updated ExeEntry, preserving existing fields not fetched from IGDB
        final updatedExe = gameEntry.exe.copyWith(
          name: game.name,
          igdbId: game.id,
          coverUrl: coverUrl, // Update original URL
          coverImageId: coverImageId, // Store image ID
          localCoverPath: localCoverPath, // Update local path
          screenshotUrls: screenshotUrls, // Update original URLs
          screenshotImageIds: screenshotImageIds, // Store image IDs
          localScreenshotPaths: localScreenshotPaths, // Update local paths
          videoIds: videoIds,
          isGame: true, // Ensure it's marked as a game
          description: game.summary,
          // notWorking, category, wineTypeOverride are preserved by copyWith
        );

        // Update via provider
        await _prefixProvider.updateExecutable(gameEntry.prefix, updatedExe);
        setState(() { _status = 'Game details updated successfully!'; });
         _printExeEntryInfo(updatedExe); // Log new details

      } else {
         setState(() { _status = 'Game detail update cancelled.'; });
      }
    } catch (e) {
       if (mounted) {
          setState(() { _status = 'Error updating game details: $e'; });
       }
       print('Error in _editGameDetails: $e');
    } finally {
       if (mounted) {
          setState(() { _isLoading = false; });
       }
    }
  }


  /// Changes the prefix assignment for a game's executable using the Provider.
  Future<void> _changeGamePrefix(GameEntry gameEntry) async {
    // Get prefixes from provider
    final currentPrefixes = _prefixProvider.prefixes;
    final prefixOptions = currentPrefixes.where((p) => p.path != gameEntry.prefix.path).toList();

    if (prefixOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other prefixes available to move to')),
      );
      return;
    }

    final selectedPrefix = await showDialog<WinePrefix>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select New Prefix'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: ListView.builder(
            itemCount: prefixOptions.length,
            itemBuilder: (context, index) {
              final prefix = prefixOptions[index];
              return ListTile(
                leading: Icon(
                  prefix.type == PrefixType.wine ? Icons.wine_bar : Icons.gamepad,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(prefix.name),
                subtitle: Text('Type: ${prefix.type.toString().split('.').last}'),
                onTap: () => Navigator.pop(context, prefix),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedPrefix != null) {
      setState(() { _isLoading = true; }); // Use provider's loading state? Maybe keep local for this UI action.
      try {
        await _prefixProvider.moveExecutableToPrefix(gameEntry.exe, gameEntry.prefix, selectedPrefix);
        // Update local status based on provider
        setState(() { _status = _prefixProvider.status; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Game moved to ${selectedPrefix.name} prefix')),
        );
      } catch (e) {
         if (mounted) {
            setState(() { _status = 'Error moving game: $e'; });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error moving game: $e')),
            );
         }
      } finally {
         if (mounted) {
            setState(() { _isLoading = false; });
         }
      }
    } else {
       if (mounted) {
          setState(() { _status = 'Prefix change cancelled.'; });
       }
    }
  }

  /// Allows the user to update the path to a game's executable file
  Future<void> _editExePath(GameEntry gameEntry) async {
    setState(() { 
      _isLoading = true; 
      _status = 'Select new executable path...'; 
    });
    
    try {
      // Pick the new executable file
      final String? newExePath = await _pickExeFile();
      
      if (newExePath == null) {
        setState(() {
          _isLoading = false;
          _status = 'Executable path update cancelled.';
        });
        return; // User cancelled
      }
      
      // Check if the file exists
      final exeFile = File(newExePath);
      if (!await exeFile.exists()) {
        setState(() {
          _isLoading = false;
          _status = 'Error: Selected file does not exist.';
        });
        return;
      }
      
      // Confirm the change
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Confirm Path Change'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Change executable path for "${gameEntry.exe.name}" from:'),
                const SizedBox(height: 8),
                Text(
                  gameEntry.exe.path,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text('To:'),
                const SizedBox(height: 8),
                Text(
                  newExePath,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      );
      
      if (confirmed != true) {
        setState(() {
          _isLoading = false;
          _status = 'Executable path update cancelled.';
        });
        return;
      }
      
      // Update the executable path via provider
      final updatedExe = gameEntry.exe.copyWith(path: newExePath);
      await _prefixProvider.updateExecutable(gameEntry.prefix, updatedExe);
      
      setState(() {
        _status = 'Executable path updated successfully.';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Executable path updated for ${gameEntry.exe.name}')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error updating executable path: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PrefixProvider>(
      builder: (context, prefixProvider, child) {
        final currentPrefixes = prefixProvider.prefixes;

        return DefaultTabController(
          length: 5,
          initialIndex: _currentTabIndex,
          child: Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).appBarTheme.backgroundColor,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title bar with window controls
                    SizedBox(
                      height: 32,
                      child: Row(
                        children: [
                          // Window controls - fix the widget reference
                          const WindowButtons(),
                          const SizedBox(width: 8),
                          // Connectivity indicator
                          Icon(
                            _isConnected ? Icons.wifi : Icons.wifi_off,
                            color: _isConnected
                                ? Theme.of(context).iconTheme.color
                                : Colors.orangeAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 16),
                          // Title
                          Expanded(
                            child: GestureDetector(
                              onPanStart: (_) => windowManager.startDragging(),
                              child: Container(
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                child: Text(
                                  'Wine Prefix Manager',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _currentTabIndex,
              type: BottomNavigationBarType.fixed,
              onTap: (index) {
                setState(() {
                  _currentTabIndex = index;
                });
              },
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.games), label: 'Library'),
                BottomNavigationBarItem(icon: Icon(Icons.category), label: 'Create'),
                BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Manage'),
                BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
                BottomNavigationBarItem(icon: Icon(Icons.article_outlined), label: 'Logs'),
              ],
            ),
            // Simplify the body to just use IndexedStack
            body: IndexedStack(
              index: _currentTabIndex,
              children: [
                _buildGameLibrary(currentPrefixes),
                PrefixCreationPage(settings: _settings),
                PrefixManagementPage(
                  settings: _settings,
                  runningProcesses: _runningProcesses,
                  onRunExe: _runExe,
                  onKillProcess: _killProcess,
                  onAddExecutable: _addExeToPrefix,
                ),
                SettingsPage(onSettingsChanged: _initialize),
                _buildLogsPage(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogsPage() {
    return const LogsPage();
  }

  Widget _buildGameLibrary(List<WinePrefix> currentPrefixes) {
    // Filter games from the prefixes passed from the consumer
    final List<GameEntry> allGames = [];
    for (final prefix in currentPrefixes) {
      for (final exe in prefix.exeEntries) {
        if (exe.isGame || exe.igdbId != null) {
          allGames.add(GameEntry(prefix: prefix, exe: exe));
        }
      }
    }

    return GameLibraryPage(
      games: allGames,
      onLaunchGame: _launchGame, // Keep local launch logic
      onShowDetails: _showGameDetails, // Keep local details dialog logic
      onGenreSelected: (genre) {
        setState(() { _selectedGenre = genre; });
      },
      selectedGenre: _selectedGenre,
      coverSize: _settings?.coverSize ?? CoverSize.medium,
      // GameLibraryPage can use Provider.of<PrefixProvider> internally if needed
    );
  }

  Future<void> _launchGame(WinePrefix prefix, ExeEntry exe) async {
    await _runExe(prefix, exe); // Uses local _runExe
  }

  Future<void> _showGameDetails(BuildContext context, GameEntry game) {
     // Use context.read to get provider instance inside the builder if needed,
     // or pass the provider instance down. Passing is simpler here.
     final prefixProvider = context.read<PrefixProvider>();

    return showDialog(
      context: context,
      // Use a Consumer inside the dialog if it needs to react to provider changes
      builder: (context) => GameDetailsDialog(
        game: game,
        settings: _settings!, // Assuming settings are loaded
        availablePrefixes: prefixProvider.prefixes, // Get prefixes from provider
        onEditGame: _editGameDetails, // Uses local method which calls provider
        onChangePrefix: _changeGamePrefix, // Uses local method which calls provider
        onLaunchGame: () {
          Navigator.pop(context);
          _launchGame(game.prefix, game.exe); // Uses local method
        },
        onMoveGameFolder: _moveGameFolder, // Uses local method which calls provider
        onToggleWorkingStatus: (gameEntry, notWorking) async {
           // Update via provider
           final updatedExe = gameEntry.exe.copyWith(notWorking: notWorking);
           await prefixProvider.updateExecutable(gameEntry.prefix, updatedExe);
           // Optionally update local status
           if(mounted) setState(() => _status = prefixProvider.status);
           // No need for local setState for prefix list update
        },
        onChangeCategory: (gameEntry, category) async {
           // Update via provider
           final updatedExe = gameEntry.exe.copyWith(category: category);
           await prefixProvider.updateExecutable(gameEntry.prefix, updatedExe);
           if(mounted) setState(() => _status = prefixProvider.status);
        },
        onEditExePath: _editExePath, // Add the new callback
      ),
    );
  }

  // Future<void> _updateGameCategory(GameEntry game, String? category) async { ... } // Removed, logic moved to dialog callback -> provider

  /// Moves the parent directory of the game's executable using the Provider.
  Future<void> _moveGameFolder(GameEntry game) async {
    String? destinationDir;
    final String folderName = path.basename(path.dirname(game.exe.path)); // Get folder name for dialog

    setState(() { _isLoading = true; _status = 'Select destination directory...'; });

    try {
      destinationDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Destination Folder for "$folderName"',
      );

      if (destinationDir == null) {
        setState(() { _status = 'Move cancelled.'; });
        return; // User cancelled
      }

      // Call provider method to handle the move and path update
      await _prefixProvider.moveGameFolderAndUpdatePath(game, destinationDir);

      // Update local status from provider
      setState(() { _status = _prefixProvider.status; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_prefixProvider.status)),
      );

    } catch (e) {
      // Provider method throws on error, catch it here for UI feedback
      print('Error moving game folder (UI): $e');
      setState(() {
        _status = 'Error moving folder: ${e.toString().replaceFirst("Exception: ", "")}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error moving folder: ${e.toString().replaceFirst("Exception: ", "")}')),
      );
    } finally {
       if (mounted) {
          setState(() { _isLoading = false; });
       }
    }
  }
}