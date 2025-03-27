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
import 'widgets/game_card.dart';
import 'widgets/game_details_dialog.dart';
import 'theme/theme_provider.dart';
import 'widgets/game_carousel.dart';
import 'pages/game_library_page.dart';
import 'pages/prefix_management_page.dart'; // Import the new page
import 'services/build_service.dart'; // Import BuildService
import 'services/igdb_service.dart'; // Import IgdbService
import 'services/prefix_storage_service.dart'; // Import PrefixStorageService
import 'services/process_service.dart'; // Import ProcessService
import 'services/prefix_creation_service.dart'; // Import PrefixCreationService
import 'services/prefix_management_service.dart'; // Import PrefixManagementService
import 'services/cover_art_service.dart'; // Import CoverArtService
import 'package:window_manager/window_manager.dart'; // Import window_manager
import 'widgets/custom_title_bar.dart'; // Import the custom title bar

Future<void> main() async { // Make main async
  WidgetsFlutterBinding.ensureInitialized(); // Ensure bindings are initialized
  // Must add this line.
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
      // size: Size(800, 600), // Optional: Set initial size
      // center: true, // Optional: Center window
      // backgroundColor: Colors.transparent, // Optional: Transparent background
      skipTaskbar: false,
      // titleBarStyle: TitleBarStyle.normal, // Default
      titleBarStyle: TitleBarStyle.hidden, // Make window chromeless
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });


  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const WinePrefixManager(),
    ),
  );
}

class WinePrefixManager extends StatelessWidget {
  const WinePrefixManager({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Wine Prefix Manager',
      theme: themeProvider.themeData,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<BaseBuild> _builds = [];
  List<WinePrefix> _prefixes = [];
  final Map<String, int> _runningProcesses = {}; // Restore map to track running processes for Game Library
  BaseBuild? _selectedBuild;
  PrefixType _selectedPrefixType = PrefixType.wine;
  // PrefixType _selectedPrefixListType = PrefixType.wine; // Removed, no longer needed for the old manage tab
  bool _isLoading = false;
  String _prefixName = '';
  String _status = '';
  Settings? _settings;
  final TextEditingController _prefixNameController = TextEditingController();
  int _currentTabIndex = 0;
  String? _selectedGenre;
  int _initialTabIndex = 2; // Start with game library view

  // Connectivity state
  bool _isConnected = true; // Assume connected initially
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // Service instances
  final BuildService _buildService = BuildService();
  final IgdbService _igdbService = IgdbService();
  final PrefixStorageService _prefixStorageService = PrefixStorageService();
  final ProcessService _processService = ProcessService();
  final PrefixCreationService _prefixCreationService = PrefixCreationService();
  final PrefixManagementService _prefixManagementService = PrefixManagementService();
  final CoverArtService _coverArtService = CoverArtService(); // Add CoverArtService instance

  @override
  void initState() {
    super.initState();
    _initialize();
    _initConnectivity(); // Check initial status
    // Listen for changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel(); // Cancel subscription
    _prefixNameController.dispose(); // Dispose existing controller
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
      print('Connectivity changed: ${_isConnected ? "Online" : "Offline"}');
    }
  }

  Future<void> _initialize() async {
    await _loadSettings();
    _fetchBuilds();
    _loadPrefixes(); // Load prefixes after settings are loaded
    _scanForPrefixes(); // Scan after loading existing prefixes
  }

  Future<void> _loadSettings() async {
    _settings = await AppSettings.load();
  }

  Future<void> _fetchBuilds() async {
    setState(() {
      _isLoading = true;
      _status = 'Fetching builds...';
    });

    try {
      final List<BaseBuild> builds = await _buildService.fetchBuilds();
      setState(() {
        _builds = builds;
        _status = 'Found ${builds.length} builds';
      });
    } catch (e) {
      setState(() {
        _status = 'Error fetching builds: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Scans for existing prefixes using PrefixManagementService and merges with current list.
  Future<void> _scanForPrefixes() async {
    if (_settings == null) {
      setState(() { _status = 'Cannot scan: Settings not loaded.'; });
      return;
    }

    setState(() { _status = 'Scanning for existing prefixes...'; });

    try {
      final scannedPrefixes = await _prefixManagementService.scanForExistingPrefixes(_settings!);

      // Merge scanned prefixes with the current list, avoiding duplicates
      // We prioritize keeping existing entries from _prefixes if paths match,
      // as they might contain exeEntries loaded from storage.
      final currentPrefixPaths = _prefixes.map((p) => p.path).toSet();
      final List<WinePrefix> newPrefixesToAdd = [];

      for (final scannedPrefix in scannedPrefixes) {
        if (!currentPrefixPaths.contains(scannedPrefix.path)) {
          // This is a newly discovered prefix, add it.
          newPrefixesToAdd.add(scannedPrefix);
          print('Discovered new prefix: ${scannedPrefix.name}');
        } else {
          // Prefix already exists, potentially update info if needed (optional)
          // For now, we just ignore it to keep the loaded exeEntries.
          print('Prefix already known: ${scannedPrefix.name}');
        }
      }

      if (newPrefixesToAdd.isNotEmpty) {
        setState(() {
          _prefixes.addAll(newPrefixesToAdd);
          _status = 'Scan complete. Added ${newPrefixesToAdd.length} new prefix(es). Total: ${_prefixes.length}.';
        });
        // Save the updated list including the newly discovered prefixes
        await _savePrefixes();
        await _checkAndDownloadMissingImages(); // Check images for newly added prefixes
      } else {
         setState(() {
           _status = 'Scan complete. No new prefixes found. Total: ${_prefixes.length}.';
         });
      }

    } catch (e) {
      setState(() {
        _status = 'Error scanning for prefixes: $e';
      });
      print('Error scanning for prefixes: $e');
    }
  }

  /// Saves the current list of prefixes using PrefixStorageService.
  Future<void> _savePrefixes() async {
    try {
      if (_settings == null) {
        print('Error saving prefixes: Settings not loaded.');
        setState(() { _status = 'Error saving prefixes: Settings not loaded.'; });
        return;
      }
      await _prefixStorageService.savePrefixes(_prefixes, _settings!); // Pass settings
      // Optionally update status: setState(() { _status = 'Prefixes saved.'; });
    } catch (e) {
      setState(() {
        _status = 'Error saving prefixes: $e';
      });
    }
  }

  // Restore _runExe and _killProcess as they are needed by the Game Library tab (_launchGame)
  /// Runs an executable using the ProcessService.
  Future<void> _runExe(WinePrefix prefix, ExeEntry exe) async {
    // Check if already running
    if (_runningProcesses.containsKey(exe.path)) {
      setState(() {
        _status = '${exe.name} is already running (PID: ${_runningProcesses[exe.path]})';
      });
      return;
    }

    setState(() {
      _isLoading = true; // Set loading true when starting
      _status = 'Starting ${exe.name}...';
    });

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
        }
      },
      onProcessExit: (exitedExePath, exitCode, errors) async { // Add async here
         // Ensure updates happen on the UI thread
        if (mounted) {
          setState(() {
            _runningProcesses.remove(exitedExePath);
            if (exitCode != 0) {
               _status = 'Error running ${exe.name} (Code: $exitCode): ${errors.join('\n')}';
            } else {
               _status = '${exe.name} exited successfully (Code: $exitCode)';
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
      return;
    }

    setState(() {
      _status = 'Attempting to kill ${exe.name} (PID: $pid)...';
    });

    final success = await _processService.killProcess(pid);

    // ProcessService's runExecutable onProcessExit callback handles removing
    // the process from _runningProcesses and updating status upon successful termination.
    // We only need to update status here if the kill command itself failed.
    if (!success && mounted) { // Check mounted after async gap
       setState(() {
         _status = 'Failed to issue kill command for ${exe.name} (PID: $pid). It might still be running.';
         // We don't remove from _runningProcesses here, as the process might still exit normally
       });
    } else if (success && mounted) {
       // Optional: Update status immediately if kill command succeeded,
       // but the onProcessExit callback provides more definitive confirmation.
       // setState(() { _status = 'Kill command sent for ${exe.name} (PID: $pid).'; });
    }
  }

  /// Loads prefixes using PrefixStorageService.
  Future<void> _loadPrefixes() async {
    setState(() { _status = 'Loading prefixes...'; });
    try {
      if (_settings == null) {
        setState(() { _status = 'Error loading prefixes: Settings not loaded.'; });
        return;
      }
      final loadedPrefixes = await _prefixStorageService.loadPrefixes(_settings!); // Pass settings
      setState(() {
        _prefixes = loadedPrefixes;
        _status = 'Loaded ${_prefixes.length} prefixes.';
      });
      await _checkAndDownloadMissingImages(); // Check for missing images after loading
    } catch (e) {
      setState(() {
        _status = 'Error loading prefixes: $e';
      });
      // Optionally print to console as well
      print('Error loading prefixes: $e');
    }
  }

  /// Downloads the selected build and creates a new prefix using PrefixCreationService.
  Future<void> _downloadAndCreatePrefix() async {
    if (_settings == null) {
       setState(() { _status = 'Settings not loaded.'; });
       return;
    }
    if (_selectedBuild == null) {
      setState(() { _status = 'Please select a build.'; });
      return;
    }
    if (_prefixName.isEmpty) {
      setState(() { _status = 'Please enter a prefix name.'; });
      return;
    }
    // Check if prefix name already exists
    if (_prefixes.any((p) => p.name == _prefixName)) {
       setState(() { _status = 'Prefix name "$_prefixName" already exists.'; });
       return;
    }


    setState(() {
      _isLoading = true;
      _status = 'Starting prefix creation...'; // Initial status
      // Reset progress if you add a progress indicator widget
    });

    try {
      final newPrefix = await _prefixCreationService.downloadAndCreatePrefix(
        selectedBuild: _selectedBuild!,
        prefixName: _prefixName,
        settings: _settings!,
        onStatusUpdate: (status) {
          // Update UI status - ensure it runs on the UI thread
          if (mounted) {
            setState(() { _status = status; });
          }
        },
        onProgressUpdate: (progress) {
          // Update UI progress indicator if you have one
          // Example: if (mounted) { setState(() { _downloadProgress = progress; }); }
          // Status is already updated with percentage in the service callback
        },
      );

      if (newPrefix != null && mounted) {
        setState(() {
          _prefixes.add(newPrefix);
          // Status already set to success message by service callback
          _prefixNameController.clear();
          _prefixName = '';
          _selectedBuild = null; // Optionally reset build selection
        });
        await _savePrefixes(); // Save the updated list
      } else if (mounted) {
         // Service returned null (error), status already updated by service callback
         print('Prefix creation failed (service returned null).');
      }

    } catch (e) {
       // Catch any unexpected errors from the service call itself
       if (mounted) {
          setState(() {
             _status = 'Unexpected error during prefix creation: $e';
          });
       }
       print('Unexpected error calling prefix creation service: $e');
    } finally {
      // Ensure isLoading is set to false regardless of success or failure
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Restore _addExeToPrefix for PrefixManagementPage callback
  Future<void> _addExeToPrefix(WinePrefix prefix) async {
    try {
      // Get exe file path
      String? filePath;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe'],
      );

      if (result != null && result.files.single.path != null) {
        filePath = result.files.single.path!;
      } else {
        // Fallback to zenity if file picker didn't work
        try {
          final shell = Shell();
          final zenityResult = await shell.run(
            'zenity --file-selection --title="Select Windows Executable" --file-filter="*.exe"'
          );
          if (zenityResult.outText.isNotEmpty) {
            filePath = zenityResult.outText.trim();
          }
        } catch (e) {
          setState(() {
            _status = 'Error: Please install zenity or try a different file picker';
          });
          return;
        }
      }

      if (filePath == null) return;

      // Ask if this is a game or regular application
      final isGame = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Game or Application?'),
          content: const Text('Is this a game or a regular application?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Application'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Game'),
            ),
          ],
        ),
      );

      if (isGame == null) return; // User cancelled

      ExeEntry exeEntry;

      if (isGame && _settings?.igdbClientId?.isNotEmpty == true) {
        // For games, search IGDB
        final filename = path.basenameWithoutExtension(filePath);

        // Show search dialog
        final game = await showDialog<IgdbGame>(
          context: context,
          builder: (context) => GameSearchDialog(
            initialQuery: filename,
            onSearch: _searchIgdbGames, // Pass the updated search function
          ),
        );

        if (game != null) {
          // User selected a game from IGDB
          setState(() {
            _status = 'Fetching game details...';
            _isLoading = true;
          });

          // Get token (now returns a map)
          final tokenResult = await _getIgdbToken();
          if (tokenResult.containsKey('error')) {
             // Handle token error (maybe show in status?)
             setState(() {
               _isLoading = false;
               _status = 'Error getting IGDB token: ${tokenResult['error']}';
             });
             // Create entry without details
             exeEntry = ExeEntry(path: filePath, name: game.name, igdbId: game.id, isGame: true);
          } else {
            final String token = tokenResult['token'];
            final coverUrl = await _fetchCoverUrl(game.cover, token);
            final screenshotUrls = await _fetchScreenshotUrls(game.screenshots, token);
            final videoIds = await _fetchGameVideoIds(game.id, token);

            // --- Get local cover path ---
            String? localCoverPath;
            if (game.id != null && coverUrl != null) {
              _status = 'Downloading cover art...'; // Update status
              localCoverPath = await _coverArtService.getLocalCoverPath(game.id!, coverUrl);
            }
            // --- End get local cover path ---

            // --- Get local screenshot paths ---
            List<String> localScreenshotPaths = [];
            if (screenshotUrls.isNotEmpty) {
              _status = 'Downloading screenshots...'; // Update status
              localScreenshotPaths = await _coverArtService.getLocalScreenshotPaths(screenshotUrls);
            }
            // --- End get local screenshot paths ---

            exeEntry = ExeEntry(
              path: filePath,
              name: game.name,
              igdbId: game.id,
              coverUrl: coverUrl, // Keep original URL for reference if needed
              localCoverPath: localCoverPath, // Add the local path
              screenshotUrls: screenshotUrls, // Keep original URLs
              localScreenshotPaths: localScreenshotPaths, // Add local paths
              videoIds: videoIds,
              isGame: true,
              description: game.summary, // Include game description
            );

            // Log created entry info
            _printExeEntryInfo(exeEntry);

            setState(() {
              _isLoading = false;
              _status = localCoverPath != null
                  ? 'Game added successfully with cover!'
                  : 'Game added (cover download failed or skipped)';
            });
          }
        } else {
          // User cancelled game selection, create regular entry
          exeEntry = ExeEntry(
            path: filePath,
            name: path.basename(filePath),
            isGame: false,
          );
        }
      } else {
        // Regular application or IGDB not configured
        exeEntry = ExeEntry(
          path: filePath,
          name: path.basename(filePath),
          isGame: isGame, // Use the result from the dialog
        );
      }

      // Add to prefix
      setState(() {
        final index = _prefixes.indexWhere((p) => p.path == prefix.path);
        if (index != -1) {
          final updatedEntries = List<ExeEntry>.from(prefix.exeEntries)..add(exeEntry);
          _prefixes[index] = WinePrefix(
            name: prefix.name,
            path: prefix.path,
            wineBuildPath: prefix.wineBuildPath,
            type: prefix.type,
            exeEntries: updatedEntries,
          );
        }
      });

      await _savePrefixes();
    } catch (e) {
      setState(() {
        _status = 'Error adding executable: $e';
        _isLoading = false;
      });
    }
  }

  // Restore _deletePrefix for PrefixManagementPage callback (Implementation needed)
  Future<void> _deletePrefix(WinePrefix prefix) async {
    // TODO: Implement confirmation dialog and deletion logic (filesystem and _prefixes list)
    print('Attempting to delete prefix: ${prefix.name}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Delete prefix ${prefix.name} (Not fully implemented)')),
    );
    // Example steps:
    // 1. Show confirmation dialog
    // 2. If confirmed, delete prefix directory (Directory(prefix.path).delete(recursive: true))
    // 3. Remove prefix from _prefixes list: setState(() => _prefixes.removeWhere((p) => p.path == prefix.path));
    // 4. Save updated _prefixes list: await _savePrefixes();
  }

  void _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          onSettingsChanged: () {
            _initialize();
          },
        ),
      ),
    );
  }

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
          _settings = await AppSettings.updateToken(_settings!, token, expiresIn);
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
      return {'error': tokenResult['error']}; // Propagate the error
    }

    final String token = tokenResult['token'];
    if (_settings == null) {
       print('Cannot search IGDB: Settings are null.');
       return {'error': 'Settings not loaded.'};
    }

    print('Searching IGDB for "$query"...'); // Log instead of setState
    try {
      final results = await _igdbService.searchIgdbGames(query, _settings!, token);
      print('Found ${results.length} game(s).'); // Log instead of setState
      return {'games': results}; // Return games list in a map
    } catch (e) {
      print('Error searching IGDB: $e'); // Log instead of setState
      return {'error': 'Error searching IGDB: $e'}; // Return error in a map
    }
  }


  /// Fetches the cover URL for a given cover ID using the IgdbService.
  Future<String?> _fetchCoverUrl(int? coverId, String token) async {
    if (coverId == null || _settings == null) return null;

    try {
      return await _igdbService.fetchCoverUrl(coverId, _settings!, token);
    } catch (e) {
      print('Error fetching cover URL in HomePage: $e');
      // Optionally update status: setState(() { _status = 'Error fetching cover: $e'; });
      return null;
    }
  }

  /// Fetches screenshot URLs for given IDs using the IgdbService.
  Future<List<String>> _fetchScreenshotUrls(List<int> screenshotIds, String token) async {
    if (screenshotIds.isEmpty || _settings == null) return [];

    try {
      return await _igdbService.fetchScreenshotUrls(screenshotIds, _settings!, token);
    } catch (e) {
      print('Error fetching screenshot URLs in HomePage: $e');
      // Optionally update status: setState(() { _status = 'Error fetching screenshots: $e'; });
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
      // Optionally update status: setState(() { _status = 'Error fetching videos: $e'; });
      return [];
    }
  }

  // Add this helper method to log video IDs
  void _printExeEntryInfo(ExeEntry entry) {
    print('Game: ${entry.name}');
    print('- IGDB ID: ${entry.igdbId}');
    print('- Has cover: ${entry.coverUrl != null}');
    print('- Screenshots: ${entry.screenshotUrls.length}');
    print('- Videos: ${entry.videoIds.length}');
    print('- Video IDs: ${entry.videoIds}');
  }

  /// Checks loaded prefixes for missing local images and attempts download.
  Future<void> _checkAndDownloadMissingImages() async {
    if (!_isConnected) {
      print("Offline, skipping check for missing images.");
      return; // Don't attempt downloads if offline
    }
    if (_settings == null) return; // Need settings for API calls

    print("Checking for missing local images...");
    bool requiresSave = false;
    int checked = 0;
    int downloadedCovers = 0;
    int downloadedScreenshots = 0;

    // Create a modifiable copy of the prefixes list
    List<WinePrefix> updatedPrefixes = List.from(_prefixes);

    for (int i = 0; i < updatedPrefixes.length; i++) {
      WinePrefix prefix = updatedPrefixes[i];
      List<ExeEntry> updatedEntries = List.from(prefix.exeEntries);
      bool prefixUpdated = false;

      for (int j = 0; j < updatedEntries.length; j++) {
        ExeEntry entry = updatedEntries[j];
        checked++;
        ExeEntry updatedEntry = entry; // Start with the original entry

        // Check cover
        if (entry.igdbId != null && entry.coverUrl != null && entry.coverUrl!.isNotEmpty && (entry.localCoverPath == null || entry.localCoverPath!.isEmpty)) {
          print("Missing local cover for ${entry.name} (${entry.igdbId}). Attempting download...");
          final localPath = await _coverArtService.getLocalCoverPath(entry.igdbId!, entry.coverUrl!);
          if (localPath != null) {
            updatedEntry = ExeEntry( // Create new entry with updated path
              path: entry.path, name: entry.name, igdbId: entry.igdbId, coverUrl: entry.coverUrl,
              localCoverPath: localPath, // Updated
              screenshotUrls: entry.screenshotUrls, localScreenshotPaths: entry.localScreenshotPaths,
              videoIds: entry.videoIds, isGame: entry.isGame, description: entry.description,
              notWorking: entry.notWorking, category: entry.category, wineTypeOverride: entry.wineTypeOverride
            );
            downloadedCovers++;
            requiresSave = true;
            prefixUpdated = true;
          }
        }

        // Check screenshots (only if cover was checked or already existed)
        if (updatedEntry.screenshotUrls.isNotEmpty && (updatedEntry.localScreenshotPaths.isEmpty || updatedEntry.localScreenshotPaths.length != updatedEntry.screenshotUrls.length)) {
           print("Missing/incomplete local screenshots for ${updatedEntry.name}. Attempting download...");
           final localPaths = await _coverArtService.getLocalScreenshotPaths(updatedEntry.screenshotUrls);
           if (localPaths.isNotEmpty && localPaths.length == updatedEntry.screenshotUrls.length) { // Check if all were downloaded
             // Create a new entry only if screenshots were successfully downloaded
             updatedEntry = ExeEntry(
               path: updatedEntry.path, name: updatedEntry.name, igdbId: updatedEntry.igdbId, coverUrl: updatedEntry.coverUrl,
               localCoverPath: updatedEntry.localCoverPath, screenshotUrls: updatedEntry.screenshotUrls,
               localScreenshotPaths: localPaths, // Updated
               videoIds: updatedEntry.videoIds, isGame: updatedEntry.isGame, description: updatedEntry.description,
               notWorking: updatedEntry.notWorking, category: updatedEntry.category, wineTypeOverride: updatedEntry.wineTypeOverride
             );
             downloadedScreenshots += localPaths.length;
             requiresSave = true;
             prefixUpdated = true;
           }
        }

        // Update the entry in the temporary list if it changed
        if (prefixUpdated) {
           updatedEntries[j] = updatedEntry;
        }
      }

      // Update the prefix in the main temporary list if any of its entries changed
      if (prefixUpdated) {
        updatedPrefixes[i] = WinePrefix(
          name: prefix.name, path: prefix.path, wineBuildPath: prefix.wineBuildPath,
          type: prefix.type, exeEntries: updatedEntries
        );
      }
    }

    print("Image check complete. Checked $checked entries. Downloaded $downloadedCovers covers, $downloadedScreenshots screenshots.");

    if (requiresSave) {
      print("Saving updated prefix data with new local image paths...");
      // Update the main state and save
      setState(() {
        _prefixes = updatedPrefixes;
        _status = "Downloaded missing images."; // Update status
      });
      await _savePrefixes();
    }
  }

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
        throw Exception('Please install zenity or try a different file picker');
      }
    } catch (e) {
      throw Exception('Error selecting file: $e');
    }
    return null;
  }

  // Removed _renamePrefix method

  // Add method to edit game details
  Future<void> _editGameDetails(GameEntry gameEntry) async {
    // Show dialog with game search option
    final filename = path.basenameWithoutExtension(gameEntry.exe.path);

    final game = await showDialog<IgdbGame>(
      context: context,
      builder: (context) => GameSearchDialog(
        initialQuery: filename,
        onSearch: _searchIgdbGames, // Pass updated search function
      ),
    );

    if (game != null) {
      setState(() {
        _status = 'Updating game details...';
        _isLoading = true;
      });

      final tokenResult = await _getIgdbToken(); // Get token map
      if (tokenResult.containsKey('error')) {
        setState(() {
          _isLoading = false;
          _status = 'Error updating details (token): ${tokenResult['error']}';
        });
        return; // Stop if token error
      }

      final String token = tokenResult['token'];
      final coverUrl = await _fetchCoverUrl(game.cover, token);
      final screenshotUrls = await _fetchScreenshotUrls(game.screenshots, token);
      final videoIds = await _fetchGameVideoIds(game.id, token);

      final updatedExe = ExeEntry(
        path: gameEntry.exe.path,
        name: game.name,
        igdbId: game.id,
        coverUrl: coverUrl,
        screenshotUrls: screenshotUrls,
        videoIds: videoIds,
        isGame: true,
        description: game.summary,  // Add game description
        // Preserve existing fields not updated by IGDB search
        notWorking: gameEntry.exe.notWorking,
        category: gameEntry.exe.category,
        wineTypeOverride: gameEntry.exe.wineTypeOverride,
      );

      // Update the exe entry in the prefix
      final prefixIndex = _prefixes.indexWhere((p) => p.path == gameEntry.prefix.path);
      if (prefixIndex != -1) {
        final exeList = List<ExeEntry>.from(_prefixes[prefixIndex].exeEntries);
        final exeIndex = exeList.indexWhere((e) => e.path == gameEntry.exe.path);

        if (exeIndex != -1) {
          exeList[exeIndex] = updatedExe;
          _prefixes[prefixIndex] = WinePrefix(
            name: _prefixes[prefixIndex].name,
            path: _prefixes[prefixIndex].path,
            wineBuildPath: _prefixes[prefixIndex].wineBuildPath,
            type: _prefixes[prefixIndex].type,
            exeEntries: exeList,
          );

          await _savePrefixes();
          setState(() {
            _status = 'Game details updated successfully!';
          });
        }
      }

      setState(() {
        _isLoading = false;
      });
    }
  }


  // Add method to change assigned prefix
  Future<void> _changeGamePrefix(GameEntry gameEntry) async {
    // Get list of prefixes as options
    final prefixOptions = _prefixes.where((p) => p.path != gameEntry.prefix.path).toList();

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
      setState(() {
        _status = 'Moving game to different prefix...';
        _isLoading = true;
      });

      try {
        // Create a copy of the executable entry to add to the new prefix
        final exeCopy = ExeEntry(
          path: gameEntry.exe.path,
          name: gameEntry.exe.name,
          igdbId: gameEntry.exe.igdbId,
          coverUrl: gameEntry.exe.coverUrl,
          screenshotUrls: gameEntry.exe.screenshotUrls,
          videoIds: gameEntry.exe.videoIds,
          isGame: gameEntry.exe.isGame,
          description: gameEntry.exe.description,
          notWorking: gameEntry.exe.notWorking,
          category: gameEntry.exe.category,
          wineTypeOverride: gameEntry.exe.wineTypeOverride,
        );

        // First, add to new prefix
        final newPrefixIndex = _prefixes.indexWhere((p) => p.path == selectedPrefix.path);
        if (newPrefixIndex != -1) {
          final updatedEntries = List<ExeEntry>.from(_prefixes[newPrefixIndex].exeEntries)
            ..add(exeCopy);

          _prefixes[newPrefixIndex] = WinePrefix(
            name: _prefixes[newPrefixIndex].name,
            path: _prefixes[newPrefixIndex].path,
            wineBuildPath: _prefixes[newPrefixIndex].wineBuildPath,
            type: _prefixes[newPrefixIndex].type,
            exeEntries: updatedEntries,
          );
        }

        // Then, remove from old prefix
        final oldPrefixIndex = _prefixes.indexWhere((p) => p.path == gameEntry.prefix.path);
        if (oldPrefixIndex != -1) {
          final updatedEntries = _prefixes[oldPrefixIndex].exeEntries
            .where((e) => e.path != gameEntry.exe.path)
            .toList();

          _prefixes[oldPrefixIndex] = WinePrefix(
            name: _prefixes[oldPrefixIndex].name,
            path: _prefixes[oldPrefixIndex].path,
            wineBuildPath: _prefixes[oldPrefixIndex].wineBuildPath,
            type: _prefixes[oldPrefixIndex].type,
            exeEntries: updatedEntries,
          );
        }

        // Save updated prefixes
        await _savePrefixes();

        setState(() {
          _status = 'Game moved to ${selectedPrefix.name} prefix';
          _isLoading = false;
        });

        // Notify the user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Game moved to ${selectedPrefix.name} prefix')),
        );
      } catch (e) {
        setState(() {
          _status = 'Error moving game: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: 0,
      child: Scaffold(
        appBar: CustomTitleBar(title: 'Wine Prefix Manager', isConnected: _isConnected), // Pass connectivity status
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          type: BottomNavigationBarType.fixed,
          onTap: (index) {
            setState(() {
              _currentTabIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.category),
              label: 'Create',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder),
              label: 'Manage',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.games),
              label: 'Library',
            ),
          ],
        ),
        body: IndexedStack(
          index: _currentTabIndex,
          children: [
            _buildWelcomePage(),
            _buildCreatePrefixTab(),
            PrefixManagementPage( // Pass necessary data and callbacks
              prefixes: _prefixes,
              runningProcesses: _runningProcesses,
              onAddExecutable: _addExeToPrefix,
              onDeletePrefix: _deletePrefix, // Placeholder implementation
              onRunExe: _runExe,
              onKillProcess: _killProcess,
            ),
            _buildGameLibrary(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Wine Prefix Manager',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Settings'),
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildCreatePrefixTab() {
    // Remove the AppBar here, as the main Scaffold now has the CustomTitleBar
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Prefix Type',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<PrefixType>(
                        segments: const [
                          ButtonSegment<PrefixType>(
                            value: PrefixType.wine,
                            label: Text('Wine'),
                            icon: Icon(Icons.wine_bar),
                          ),
                          ButtonSegment<PrefixType>(
                            value: PrefixType.proton,
                            label: Text('Proton'),
                            icon: Icon(Icons.games),
                          ),
                        ],
                        selected: {_selectedPrefixType},
                        onSelectionChanged: (Set<PrefixType> newSelection) {
                          setState(() {
                            _selectedPrefixType = newSelection.first;
                            _selectedBuild = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Build',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _builds.where((build) => build.type == _selectedPrefixType).isEmpty
                          ? Center(
                              child: Column(
                                children: [
                                  const Text('No builds available.'),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    onPressed: _fetchBuilds,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Refresh'),
                                  ),
                                ],
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<BaseBuild>(
                                  value: _selectedBuild,
                                  onChanged: (BaseBuild? newValue) {
                                    setState(() {
                                      _selectedBuild = newValue;
                                    });
                                  },
                                  hint: const Text('   Select a build'),
                                  isExpanded: true,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  items: _builds
                                      .where((build) => build.type == _selectedPrefixType)
                                      .map((build) {
                                    return DropdownMenuItem<BaseBuild>(
                                      value: build,
                                      child: Text(build.name),

                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ),

              Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Prefix Name',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _prefixNameController,
                        decoration: InputDecoration(
                          hintText: 'Enter a name for the prefix',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.create_new_folder),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _prefixName = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: (_isLoading || _selectedBuild == null || _prefixName.isEmpty)
                    ? null
                    : _downloadAndCreatePrefix,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  icon: const Icon(Icons.add_circle),
                  label: const Text(
                    'Create Prefix',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Card(
                    color: _status.contains('Error')
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            _status.contains('Error') ? Icons.error : Icons.info,
                            color: _status.contains('Error')
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _status,
                              style: TextStyle(
                                color: _status.contains('Error')
                                  ? Theme.of(context).colorScheme.onErrorContainer
                                  : Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Removed _buildManagePrefixesTab method as its functionality is now in PrefixManagementPage

  Widget _buildGameLibrary() {
    final List<GameEntry> allGames = [];
    for (final prefix in _prefixes) {
      for (final exe in prefix.exeEntries) {
        if (exe.isGame || exe.igdbId != null) {
          allGames.add(GameEntry(prefix: prefix, exe: exe));
        }
      }
    }

    return GameLibraryPage(
      games: allGames,
      onLaunchGame: _launchGame,
      onShowDetails: _showGameDetails,
      onGenreSelected: (genre) {
        setState(() {
          _selectedGenre = genre;
        });
      },
      selectedGenre: _selectedGenre,
      coverSize: _settings?.coverSize ?? CoverSize.medium,
    );
  }

  Future<void> _launchGame(WinePrefix prefix, ExeEntry exe) async {
    await _runExe(prefix, exe);
  }

  Future<void> _showGameDetails(BuildContext context, GameEntry game) {
    return showDialog(
      context: context,
      builder: (context) => GameDetailsDialog(
        game: game,
        settings: _settings!,
        availablePrefixes: _prefixes,
        onEditGame: _editGameDetails,
        onChangePrefix: _changeGamePrefix,
        onLaunchGame: () {
          Navigator.pop(context);
          _launchGame(game.prefix, game.exe);
        },
        onMoveGameFolder: _moveGameFolder, // Add this line
        onToggleWorkingStatus: (gameEntry, notWorking) {
          // Update UI state immediately
          setState(() {
            final index = _prefixes.indexWhere((p) => p.path == gameEntry.prefix.path);
            if (index != -1) {
              final exeList = List<ExeEntry>.from(_prefixes[index].exeEntries);
              final exeIndex = exeList.indexWhere((e) => e.path == gameEntry.exe.path);
              if (exeIndex != -1) {
                exeList[exeIndex] = ExeEntry(
                  path: gameEntry.exe.path,
                  name: gameEntry.exe.name,
                  igdbId: gameEntry.exe.igdbId,
                  coverUrl: gameEntry.exe.coverUrl,
                  screenshotUrls: gameEntry.exe.screenshotUrls,
                  videoIds: gameEntry.exe.videoIds,
                  isGame: gameEntry.exe.isGame,
                  description: gameEntry.exe.description,
                  notWorking: notWorking,
                  category: gameEntry.exe.category,
                  wineTypeOverride: gameEntry.exe.wineTypeOverride, // Preserve override
                );
                _prefixes[index] = WinePrefix(
                  name: _prefixes[index].name,
                  path: _prefixes[index].path,
                  wineBuildPath: _prefixes[index].wineBuildPath,
                  type: _prefixes[index].type,
                  exeEntries: exeList,
                );
              }
            }
          });
          // Save changes asynchronously
          _savePrefixes();
        },
        onChangeCategory: _updateGameCategory,
      ),
    );
  }

  Future<void> _updateGameCategory(GameEntry game, String? category) async {
    final prefixIndex = _prefixes.indexWhere((p) => p.path == game.prefix.path);
    if (prefixIndex != -1) {
      final exeList = List<ExeEntry>.from(_prefixes[prefixIndex].exeEntries);
      final exeIndex = exeList.indexWhere((e) => e.path == game.exe.path);

      if (exeIndex != -1) {
        final updatedExe = ExeEntry(
          path: game.exe.path,
          name: game.exe.name,
          igdbId: game.exe.igdbId,
          coverUrl: game.exe.coverUrl,
          screenshotUrls: game.exe.screenshotUrls,
          videoIds: game.exe.videoIds,
          isGame: game.exe.isGame,
          description: game.exe.description,
          notWorking: game.exe.notWorking,
          category: category,
          wineTypeOverride: game.exe.wineTypeOverride, // Preserve override
        );

        exeList[exeIndex] = updatedExe;
        _prefixes[prefixIndex] = WinePrefix(
          name: _prefixes[prefixIndex].name,
          path: _prefixes[prefixIndex].path,
          wineBuildPath: _prefixes[prefixIndex].wineBuildPath,
          type: _prefixes[prefixIndex].type,
          exeEntries: exeList,
        );

        await _savePrefixes();
        setState(() {});
      }
    }
  }

  /// Moves the parent directory of the game's executable to a new location.
  Future<void> _moveGameFolder(GameEntry game) async {
    final String currentExePath = game.exe.path;
    // Ensure we have an absolute path before getting the dirname
    final String absoluteExePath = path.isAbsolute(currentExePath)
        ? currentExePath
        : path.absolute(currentExePath); // This might need context if CWD changes, but should be okay here.

    // Check if the path is valid and exists before proceeding
    final exeFile = File(absoluteExePath);
    if (!await exeFile.exists()) {
      if (mounted) {
        setState(() {
          _status = 'Error: Executable path "$absoluteExePath" does not exist.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: Executable path does not exist.')),
        );
      }
      return;
    }

    final String currentParentDir = path.dirname(absoluteExePath);
    final String folderName = path.basename(currentParentDir);

    // Check if the parent directory exists
    final parentDir = Directory(currentParentDir);
     if (!await parentDir.exists()) {
      if (mounted) {
        setState(() {
          _status = 'Error: Parent directory "$currentParentDir" does not exist.';
        });
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: Game folder does not exist.')),
        );
      }
      return;
    }


    if (mounted) {
      setState(() {
        _status = 'Select destination directory for "$folderName"...';
      });
    }

    String? destinationDir;
    try {
      // Use file picker to get the destination directory
      destinationDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Destination Folder for "$folderName"',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error opening directory picker: $e';
        });
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening directory picker: $e')),
        );
      }
      return;
    }

    if (destinationDir == null) {
      if (mounted) {
        setState(() {
          _status = 'Move cancelled.';
        });
      }
      return; // User cancelled
    }

    final String newParentDir = path.join(destinationDir, folderName);

    // Prevent moving into itself or if destination is the same
    if (path.equals(newParentDir, currentParentDir)) {
       if (mounted) {
        setState(() {
          _status = 'Source and destination are the same. Move cancelled.';
        });
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Source and destination are the same.')),
        );
      }
      return;
    }

    // Check if destination already exists
    final newDir = Directory(newParentDir);
    if (await newDir.exists()) {
      if (mounted) {
        setState(() {
          _status = 'Error: Destination "$newParentDir" already exists.';
        });
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: Destination folder "$folderName" already exists.')),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _status = 'Moving "$currentParentDir" to "$newParentDir"...';
      });
    }

    try {
      // Use 'mv' command via Shell for moving the directory
      final shell = Shell();
      // Ensure paths are quoted to handle spaces and special characters
      final command = 'mv "${currentParentDir}" "${destinationDir}"'; // Move into the selected destination
      print('Executing move command: $command');
      final results = await shell.run(command);

      // shell.run returns a List<ProcessResult>, access the first one
      final result = results.first;

      if (result.exitCode != 0) {
        // Attempt to parse stderr for a more specific error message
        String errorMsg = result.errText.trim();
        if (errorMsg.isEmpty) {
          errorMsg = 'Unknown error (exit code ${result.exitCode})';
        }
        throw Exception('Failed to move directory: $errorMsg');
      }

      // Calculate the new executable path relative to the *new* parent directory
      final String relativeExePath = path.relative(absoluteExePath, from: currentParentDir);
      final String newExePath = path.join(newParentDir, relativeExePath);

      // Update the ExeEntry in the state
      final prefixIndex = _prefixes.indexWhere((p) => p.path == game.prefix.path);
      if (prefixIndex != -1) {
        final exeList = List<ExeEntry>.from(_prefixes[prefixIndex].exeEntries);
        // Find the specific exe entry using the *original* path
        final exeIndex = exeList.indexWhere((e) => e.path == currentExePath);

        if (exeIndex != -1) {
          final updatedExe = ExeEntry(
            path: newExePath, // *** Update the path ***
            name: game.exe.name,
            igdbId: game.exe.igdbId,
            coverUrl: game.exe.coverUrl,
            screenshotUrls: game.exe.screenshotUrls,
            videoIds: game.exe.videoIds,
            isGame: game.exe.isGame,
            description: game.exe.description,
            notWorking: game.exe.notWorking,
            category: game.exe.category,
            wineTypeOverride: game.exe.wineTypeOverride,
          );

          exeList[exeIndex] = updatedExe;
          _prefixes[prefixIndex] = WinePrefix(
            name: _prefixes[prefixIndex].name,
            path: _prefixes[prefixIndex].path,
            wineBuildPath: _prefixes[prefixIndex].wineBuildPath,
            type: _prefixes[prefixIndex].type,
            exeEntries: exeList,
          );

          await _savePrefixes();

          if (mounted) {
            setState(() {
              _status = 'Successfully moved "$folderName" to "$destinationDir" and updated path.';
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Moved "$folderName" successfully.')),
            );
          }
        } else {
           // This case should ideally not happen if the GameEntry was valid
           throw Exception('Consistency error: Could not find executable entry with path "$currentExePath" in prefix "${game.prefix.name}" to update after move.');
        }
      } else {
         // This case should ideally not happen
         throw Exception('Consistency error: Could not find prefix entry with path "${game.prefix.path}" to update after move.');
      }

    } catch (e) {
      print('Error moving game folder: $e'); // Log detailed error
      if (mounted) {
        setState(() {
          // Provide a user-friendly error message
          _status = 'Error moving folder: ${e.toString().replaceFirst("Exception: ", "")}';
          _isLoading = false;
        });
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error moving folder: ${e.toString().replaceFirst("Exception: ", "")}')),
         );
      }
      // Note: No automatic rollback implemented. The move might be partially complete.
    }
  }
}