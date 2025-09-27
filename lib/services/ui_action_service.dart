import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// Models
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../models/igdb_models.dart';

// Providers
import '../providers/prefix_provider.dart';
// Removed: import '../providers/game_provider.dart'; // Does not exist
// Removed: import '../providers/log_provider.dart'; // Does not exist
// Removed: duplicate import '../providers/prefix_provider.dart';

// Services
import 'log_service.dart';
import 'igdb_service.dart';
import 'process_service.dart';
import 'prefix_management_service.dart';
import '../config/api_keys.dart';

// Widgets & Dialogs
// Corrected paths to ../widgets/ for dialogs that exist there.
// Removed ../pages/ imports for dialogs as they are mostly widgets or handled by navigation to pages.
import '../widgets/game_details_dialog.dart';
import '../widgets/game_search_dialog.dart'; // Corrected from pages
import '../widgets/common_components_dialog.dart';
// This was likely prefix_selection_dialog
import '../widgets/text_input_dialog.dart';
// Other dialogs like edit_game_dialog, prefix_creation_dialog, confirmation_dialog, message_dialog
// might be specific widgets or part of page navigation logic, not direct imports here unless they are generic dialog widgets.
// For now, keeping only the ones that are clearly generic dialog widgets used by this service.
// If specific page-based dialogs are needed, they are usually invoked via Navigator.push with the page route.

// TODO: Create a Winetricks Verbs Dialog widget
// import '../widgets/winetricks_verbs_dialog.dart';

class UIActionService {
  final LogService _logService;
  // Keep references to other services needed by the methods
  final IgdbService _igdbService;
  final ProcessService _processService;
  final PrefixProvider _prefixProvider; // Need provider for updates
  final Settings _settings; // Need settings
  // Add PrefixManagementService if needed by runWinecfg later
  final PrefixManagementService _prefixManagementService; // Added

  // Constructor updated to accept necessary services/providers/settings
  UIActionService({
    required LogService logService,
    required IgdbService igdbService,
    required ProcessService processService,
    required PrefixProvider prefixProvider,
    required Settings settings,
    // Inject PrefixManagementService
    PrefixManagementService? prefixManagementService, // Make optional for now
  })  : _logService = logService,
        _igdbService = igdbService,
        _processService = processService,
        _prefixProvider = prefixProvider,
        _settings = settings,
        // Initialize, potentially with a default instance if not provided
        _prefixManagementService =
            prefixManagementService ?? PrefixManagementService();

  // Removed _addLog helper, using _logService.log directly

  /// Handles picking an executable file, asking if it's a game, fetching IGDB data if needed,
  /// and adding it to a prefix via the provider.
  Future<void> addExecutableToPrefix(
      BuildContext context, WinePrefix prefix) async {
    // Make sure we're using the root navigator context for dialogs
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    try {
      final typeGroup =
          const XTypeGroup(label: 'Executables', extensions: ['exe', 'msi', 'bat']);
      final result = await openFile(acceptedTypeGroups: [typeGroup]);

      if (result == null) {
        _logService.log('Executable selection cancelled.');
        return;
      }

      final filePath = result.path;
      final fileName = p.basename(filePath);
      final exeName = p.basenameWithoutExtension(fileName);

      // Check if executable already exists in this prefix
      if (_prefixProvider.prefixes
          .firstWhere((p) => p.path == prefix.path)
          .exeEntries
          .any((e) => e.path == filePath)) {
        _logService.log(
            'Executable "$fileName" already exists in prefix "${prefix.name}".');
        if (rootContext.mounted) {
          ScaffoldMessenger.of(rootContext).showSnackBar(
            SnackBar(
                content: Text(
                    'Executable "$fileName" already exists in this prefix.')),
          );
        }
        return;
      }

      // --- Ask if it's a game ---
      final isGame = await showDialog<bool>(
        context: rootContext,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add Executable'),
          content: Text('Is "$exeName" a game?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false), // No
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true), // Yes
              child: const Text('Yes'),
            ),
          ],
        ),
      );

      if (isGame == null) {
        _logService.log('Add executable cancelled by user.');
        return; // User cancelled the dialog
      }

      ExeEntry finalExeEntry;

      if (isGame) {
        // --- Get Game Name for Search ---
        final gameNameToSearch = await showDialog<String>(
          context: rootContext,
          builder: (dialogContext) => TextInputDialog(
            title: 'Enter Game Name',
            labelText: 'Game Name for IGDB Search',
            initialValue: exeName, // Pre-fill with exe name
            confirmButtonText: 'Search IGDB',
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Name cannot be empty'
                : null,
          ),
        );

        if (gameNameToSearch == null || gameNameToSearch.isEmpty) {
          _logService.log(
              'IGDB search cancelled or name empty. Adding as game without metadata.');
          finalExeEntry = ExeEntry(path: filePath, name: exeName, isGame: true);
        } else {
          // --- Search IGDB ---
          _logService.log('Searching IGDB for "$gameNameToSearch"...');
          ExeEntry tempEntry = ExeEntry(
              path: filePath,
              name: exeName,
              isGame: true); // Start with basic game entry
          String igdbStatus = "";

          try {
            final tokenData = await _igdbService.getIgdbToken(_settings);
            if (tokenData != null && tokenData['token'] != null) {
              final token = tokenData['token'] as String;
              final searchResults = await _igdbService.searchIgdbGames(
                  gameNameToSearch, _settings, token);

              if (searchResults.isNotEmpty) {
                // TODO: Potentially show a selection dialog if multiple results?
                // For now, just take the first result.
                final IgdbGame firstMatch = searchResults.first;
                _logService.log(
                    'Found IGDB match: ${firstMatch.name} (ID: ${firstMatch.id})');

                // Fetch details
                final coverDetails = await _igdbService.fetchCoverDetails(
                    firstMatch.cover, _settings, token);
                final screenshotDetails =
                    await _igdbService.fetchScreenshotDetails(
                        firstMatch.screenshots, _settings, token);
                final videoIds = await _igdbService.fetchGameVideoIds(
                    firstMatch.id, _settings, token);

                // Enrich the entry
                tempEntry = tempEntry.copyWith(
                  igdbId: firstMatch.id,
                  description: firstMatch.summary,
                  igdbCoverId: firstMatch.cover,
                  coverUrl: coverDetails?['url'],
                  coverImageId: coverDetails?['imageId'],
                  igdbScreenshotIds: firstMatch.screenshots,
                  screenshotUrls:
                      screenshotDetails.map((s) => s['url']!).toList(),
                  screenshotImageIds:
                      screenshotDetails.map((s) => s['imageId']!).toList(),
                  videoIds: videoIds,
                );
                igdbStatus = " Found IGDB details.";
              } else {
                igdbStatus = " No IGDB details found.";
                _logService
                    .log('No IGDB match found for query: "$gameNameToSearch"');
              }
            } else {
              igdbStatus = " Could not get IGDB token.";
              _logService.log('Failed to get IGDB token, skipping fetch.');
            }
          } catch (e) {
            igdbStatus = " Error fetching IGDB details: $e";
            _logService.log('Error during IGDB fetch: $e', LogLevel.error);
          }
          finalExeEntry = tempEntry; // Use the potentially enriched entry
          _logService.log('IGDB Fetch Status: $igdbStatus');
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(
                  content: Text('IGDB Fetch: ${igdbStatus.trim()}'),
                  duration: const Duration(seconds: 2)),
            );
          }
        }
      } else {
        // Not a game
        finalExeEntry = ExeEntry(path: filePath, name: exeName, isGame: false);
      }

      // --- Add the final ExeEntry using the provider ---
      await _prefixProvider.addExecutable(prefix, finalExeEntry);

      // Show final status from provider
      if (rootContext.mounted) {
        ScaffoldMessenger.of(rootContext).showSnackBar(
          SnackBar(
              content: Text(_prefixProvider.status),
              duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      _logService.log('Error adding executable: $e', LogLevel.error);
      if (rootContext.mounted) {
        ScaffoldMessenger.of(rootContext).showSnackBar(
          SnackBar(
              content: Text('Error adding executable: $e'),
              duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  /// Launches the specified game executable.
  /// Accepts optional callbacks for process start and exit.
  Future<void> launchGame(
    GameEntry entry, {
    Function(String exePath, int pid)? onProcessStart,
    Function(String exePath, int exitCode, List<String> errors)? onProcessExit,
  }) async {
    _logService.log('Attempting to run ${entry.exe.name}...');
    try {
      // Use injected ProcessService instance and pass callbacks
      await _processService.runExecutable(
        entry.prefix,
        entry.exe,
        onProcessStart: (exePath, pid) {
          _logService.log('Started ${p.basename(exePath)} (PID: $pid)');
          onProcessStart?.call(exePath, pid); // Call the provided callback
        },
        onProcessExit: (exePath, exitCode, errors) {
          _logService.log('${p.basename(exePath)} exited with code $exitCode.');
          if (errors.isNotEmpty) {
            _logService.log('Errors:\n${errors.join('\n')}', LogLevel.warning);
          }
          onProcessExit?.call(
              exePath, exitCode, errors); // Call the provided callback
        },
      );
    } catch (e) {
      _logService.log('Error running executable: $e', LogLevel.error);
      // Rethrow the error so the caller can handle UI state reset
      rethrow;
    }
  }

  /// Shows the Game Details Dialog and handles its actions.
  Future<void> showGameDetails(
      BuildContext scaffoldContext, GameEntry entry) async {
    // Get the latest settings by directly accessing the field
    // final Settings currentSettings = _settings; // No longer need to get settings for this check

    // Ensure settings are loaded before showing details that might need IGDB
    // Check global API keys instead of settings
    if (globalIgdbClientId.isEmpty || globalIgdbClientSecret.isEmpty) {
      _logService.log(
          'Global IGDB credentials not set. Cannot fetch full details.',
          LogLevel.warning);
      // Optionally show the dialog with limited info or prevent opening
    }

    // Use the scaffoldContext passed from the page
    // Check mount status before showing dialog
    if (!scaffoldContext.mounted) return;

    // Need to get available prefixes for the dialog's potential 'Change Prefix' feature
    // Assuming PrefixProvider holds the list
    final availablePrefixes = _prefixProvider.prefixes;

    await showDialog(
      context: scaffoldContext, // Use the correct context
      builder: (dialogContext) => GameDetailsDialog(
        // This is the GameDetailsDialog context
        game: entry, // Use 'game' parameter name
        settings: _settings, // Use instance field settings
        availablePrefixes: availablePrefixes, // Pass available prefixes
        // prefixProvider: _prefixProvider, // Pass provider instance - Removed from GameDetailsDialog
        onLaunchGame: () async {
          // Close dialog before launching
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
          // Launch the game
          await launchGame(entry);
        },
        onEditExePath: (gameEntry) async {
          // FIX: Rename parameter to onEditExePath
          final typeGroup = const XTypeGroup(
              label: 'Executables', extensions: ['exe', 'msi', 'bat']);
          final result = await openFile(
              acceptedTypeGroups: [typeGroup],
              initialDirectory: p.dirname(gameEntry.exe.path));
          if (result != null) {
            final newPath = result.path;
            // Use injected PrefixProvider instance
            await _prefixProvider.updateExecutablePath(
                gameEntry.prefix, gameEntry.exe, newPath); // Use gameEntry
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          }
        },
        onUpdateMetadata: (gameEntry) async {
          // Adjusted signature
          _logService.log(
              'Metadata update requested for ${gameEntry.exe.name}'); // Use log
          // Check mount status before showing nested dialog
          if (!scaffoldContext.mounted) return;

          final searchResult = await showDialog<IgdbGame>(
            context: scaffoldContext,
            builder: (_) => GameSearchDialog(
              initialQuery: gameEntry.exe.name, // Use gameEntry
              onSearch: (query) async {
                // Use injected IgdbService and Settings instances
                final tokenData = await _igdbService.getIgdbToken(_settings);
                if (tokenData == null) {
                  return {'error': 'Could not get IGDB token'};
                }
                final games = await _igdbService.searchIgdbGames(
                    query, _settings, tokenData['token']);
                return {'games': games};
              },
            ),
          );

          // Check mount status again after await
          if (searchResult != null && scaffoldContext.mounted) {
            ExeEntry updatedExe = gameEntry.exe; // Use gameEntry
            _logService.log(
                'Fetching full details for ${searchResult.name} (ID: ${searchResult.id})...'); // Use log
            try {
              final tokenData = await _igdbService.getIgdbToken(_settings);
              if (tokenData != null && tokenData['token'] != null) {
                final token = tokenData['token'] as String;
                final coverDetails = await _igdbService.fetchCoverDetails(
                    searchResult.cover, _settings, token);
                // Removed redundant '?? []' as searchResult.screenshots is non-nullable
                final screenshotDetails =
                    await _igdbService.fetchScreenshotDetails(
                        searchResult.screenshots, _settings, token);
                final videoIds = await _igdbService.fetchGameVideoIds(
                    searchResult.id, _settings, token);

                updatedExe = gameEntry.exe.copyWith(
                  // Use gameEntry
                  igdbId: searchResult.id,
                  description: searchResult.summary,
                  igdbCoverId: searchResult.cover,
                  coverUrl: coverDetails?['url'],
                  coverImageId: coverDetails?['imageId'],
                  igdbScreenshotIds: searchResult.screenshots,
                  screenshotUrls:
                      screenshotDetails.map((s) => s['url']!).toList(),
                  screenshotImageIds:
                      screenshotDetails.map((s) => s['imageId']!).toList(),
                  videoIds: videoIds,
                  isGame: true,
                );
                _logService.log(
                    'Successfully fetched full details for ${searchResult.name}.'); // Use log
              } else {
                _logService.log(
                    'Could not get IGDB token to fetch full details.',
                    LogLevel.warning); // FIX: Use positional level
                updatedExe = gameEntry.exe
                    .copyWith(igdbId: searchResult.id); // Use gameEntry
              }
            } catch (e) {
              _logService.log(
                  'Error fetching full IGDB details: $e. Updating ID only.',
                  LogLevel.error); // FIX: Use positional level
              updatedExe = gameEntry.exe
                  .copyWith(igdbId: searchResult.id); // Use gameEntry
            }

            // Use injected PrefixProvider instance
            await _prefixProvider.updateExecutable(
                gameEntry.prefix, updatedExe); // Use gameEntry
            _logService.log(
                'Updated metadata for ${gameEntry.exe.name} from search.'); // Use log

            // Pop the details dialog
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          }
        },
        onSaveLaunchOptions: (gameEntry, options) async {
          // Adjusted signature
          // Use injected PrefixProvider instance
          await _prefixProvider.updateExecutable(gameEntry.prefix,
              gameEntry.exe.copyWith(launchOptions: options)); // Use gameEntry
          _logService.log(
              'Launch options updated for ${gameEntry.exe.name}.'); // Use log
        },
        // onSaveSteamAppId: (gameEntry, appId) async { // Removed callback
        //    // Use injected PrefixProvider instance
        //    await _prefixProvider.updateExecutable(gameEntry.prefix, gameEntry.exe.copyWith(steamAppId: appId)); // Use gameEntry
        //    _logService.log('Steam App ID updated for ${gameEntry.exe.name}.'); // Use log
        // },
        // Add other required callbacks from GameDetailsDialog constructor
        onChangeCategory: (gameEntry, category) async {
          // Adjusted signature
          await _prefixProvider.updateExecutable(
              gameEntry.prefix, gameEntry.exe.copyWith(category: category));
          _logService.log('Category changed for ${gameEntry.exe.name}');
        },
        onToggleWorkingStatus: (gameEntry, notWorking) async {
          // Add missing parameter
          await _prefixProvider.updateExecutable(
              gameEntry.prefix, gameEntry.exe.copyWith(notWorking: notWorking));
          _logService.log('Working status toggled for ${gameEntry.exe.name}');
        },
      ),
    );
  }

  /// Shows the Common Components Dialog.
  Future<void> showCommonComponentsDialog(
      BuildContext scaffoldContext, WinePrefix prefix) async {
    // Check mount status before showing dialog
    if (!scaffoldContext.mounted) return;
    await showDialog(
      context: scaffoldContext, // Use scaffoldContext
      builder: (dialogContext) => CommonComponentsDialog(
        prefix: prefix,
        settings: _settings, // FIX: Pass the required settings object
        // The actual installation logic likely happens within CommonComponentsDialog
        // or calls another service method passed into it. This service method
        // is primarily responsible for *showing* the dialog.
      ),
    );
    // Log that the dialog was opened, if desired
    // _logService.log('Opened common components dialog for ${prefix.name}.'); // Use log
  }

  /// Allows the user to pick an installer file and runs it within the prefix.
  Future<void> runInstallerInPrefix(
      BuildContext context, WinePrefix prefix) async {
    try {
      final typeGroup =
          const XTypeGroup(label: 'Installers', extensions: ['exe', 'msi']);
      final result = await openFile(acceptedTypeGroups: [typeGroup]);
      if (result != null) {
        final installerPath = result.path;
        final installerName = p.basename(installerPath);

        _logService.log(
            'Attempting to run installer "$installerName" in prefix "${prefix.name}"...');

        // Create a temporary ExeEntry for the installer
        final installerExe = ExeEntry(path: installerPath, name: installerName);

        // Run the installer using ProcessService
        // FIX: Provide required callbacks
        await _processService.runExecutable(
          prefix,
          installerExe,
          onProcessStart: (exePath, pid) {
            _logService.log('Started installer $installerName (PID: $pid)');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Started installer $installerName...')),
              );
            }
          },
          onProcessExit: (exePath, exitCode, errors) {
            _logService
                .log('Installer $installerName exited with code $exitCode.');
            if (errors.isNotEmpty) {
              _logService.log(
                  'Installer errors:\n${errors.join('\n')}', LogLevel.warning);
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Installer $installerName finished (Code: $exitCode)')),
              );
            }
            // Suggest rescanning or adding executable manually after install?
          },
        );
        // Removed redundant snackbar here, handled by onProcessExit
        // if (context.mounted) {
        //   ScaffoldMessenger.of(context).showSnackBar(
        //     SnackBar(content: Text('Installer $installerName finished.')),
        //   );
        // }
      } else {
        _logService.log('Installer selection cancelled.');
      }
    } catch (e) {
      _logService.log('Error running installer: $e', LogLevel.error);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error running installer: $e')),
        );
      }
    }
  }

  /// Opens the prefix directory in the system file manager.
  Future<void> explorePrefixFiles(WinePrefix prefix) async {
    final path = prefix.path;
    _logService.log('Attempting to open prefix directory: $path');
    try {
      // Try to use xdg-open on Linux
      final result = await Process.run('xdg-open', [path]);

      if (result.exitCode != 0) {
        _logService.log(
            'Error opening file explorer: ${result.stderr}', LogLevel.error);
      }
    } catch (e) {
      _logService.log('Error launching file explorer: $e', LogLevel.error);
    }
  }

  // Removed showWinetricksVerbsDialog method

  /// Adds a specific ExeEntry to a prefix (used for compressed games)
  Future<void> addSpecificExecutableToPrefix(
      WinePrefix prefix, ExeEntry exeEntry) async {
    try {
      await _prefixProvider.addExecutable(prefix, exeEntry);
      _logService.log(
          'Added executable "${exeEntry.name}" to prefix "${prefix.name}"');

      // For compressed games, also try to fetch metadata
      if (exeEntry.isCompressed) {
        await _tryFetchMetadataForCompressedGame(prefix, exeEntry);
      }
    } catch (e) {
      _logService.log('Error adding executable to prefix: $e', LogLevel.error);
      rethrow;
    }
  }

  /// Try to fetch metadata for compressed games
  Future<void> _tryFetchMetadataForCompressedGame(
      WinePrefix prefix, ExeEntry compressedGame) async {
    try {
      _logService
          .log('Fetching metadata for compressed game: ${compressedGame.name}');

      final tokenData = await _igdbService.getIgdbToken(_settings);
      if (tokenData != null && tokenData['token'] != null) {
        final token = tokenData['token'] as String;
        final searchResults = await _igdbService.searchIgdbGames(
            compressedGame.name, _settings, token);

        if (searchResults.isNotEmpty) {
          final firstMatch = searchResults.first;
          _logService
              .log('Found IGDB match for compressed game: ${firstMatch.name}');

          // Fetch details
          final coverDetails = await _igdbService.fetchCoverDetails(
              firstMatch.cover, _settings, token);
          final screenshotDetails = await _igdbService.fetchScreenshotDetails(
              firstMatch.screenshots, _settings, token);
          final videoIds = await _igdbService.fetchGameVideoIds(
              firstMatch.id, _settings, token);

          // Update the compressed game with metadata
          final updatedGame = compressedGame.copyWith(
            igdbId: firstMatch.id,
            description: firstMatch.summary,
            igdbCoverId: firstMatch.cover,
            coverUrl: coverDetails?['url'],
            coverImageId: coverDetails?['imageId'],
            igdbScreenshotIds: firstMatch.screenshots,
            screenshotUrls: screenshotDetails.map((s) => s['url']!).toList(),
            screenshotImageIds:
                screenshotDetails.map((s) => s['imageId']!).toList(),
            videoIds: videoIds,
          );

          await _prefixProvider.updateExecutable(prefix, updatedGame);
          _logService.log('Updated compressed game with IGDB metadata');
        }
      }
    } catch (e) {
      _logService.log(
          'Could not fetch metadata for compressed game: $e', LogLevel.warning);
      // Don't rethrow - metadata is optional
    }
  }

  /// Shows a dialog to edit environment variables for a Wine prefix
  Future<void> editPrefixEnvironmentVariables(
      BuildContext context, WinePrefix prefix) async {
    // Get the existing environment variables
    Map<String, String> envVars = {...prefix.environmentVariables};

    // Show the dialog
    await _showEnvironmentVarsDialog(context, prefix, envVars);

    return;
  }

  Future<void> _showEnvironmentVarsDialog(BuildContext context,
      WinePrefix prefix, Map<String, String> initialVars) async {
    final newKeyController = TextEditingController();
    final newValueController = TextEditingController();

    // Convert map to list of controllers for easier manipulation
    List<MapEntry<String, TextEditingController>> controllers = initialVars
        .entries
        .map((e) => MapEntry(e.key, TextEditingController(text: e.value)))
        .toList();

    // Show dialog with a stateful builder to manage state
    bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Environment Variables'),
              content: SizedBox(
                width: 500,
                height: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: controllers.length,
                        itemBuilder: (context, index) {
                          final entry = controllers[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 180,
                                  child: Text(
                                    entry.key,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: entry.value,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      controllers.removeAt(index);
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    const Text('Add New Variable',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: newKeyController,
                            decoration: const InputDecoration(
                              hintText: 'Variable Name',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: newValueController,
                            decoration: const InputDecoration(
                              hintText: 'Value',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, color: Colors.green),
                          onPressed: () {
                            if (newKeyController.text.isNotEmpty) {
                              setState(() {
                                controllers.add(
                                  MapEntry(
                                    newKeyController.text,
                                    TextEditingController(
                                        text: newValueController.text),
                                  ),
                                );
                                newKeyController.clear();
                                newValueController.clear();
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    // Update the environment variables
                    Map<String, String> updatedEnvVars = {};
                    for (var entry in controllers) {
                      updatedEnvVars[entry.key] = entry.value.text;
                    }

                    // Return the updated variables
                    Navigator.of(context).pop(true);

                    // Update the prefix with new environment variables
                    final updatedPrefix = prefix.copyWith(
                      environmentVariables: updatedEnvVars,
                    );

                    // Save the updated prefix
                    _prefixProvider.updatePrefix(updatedPrefix);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
