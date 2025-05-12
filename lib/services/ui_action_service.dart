import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart'; // Added for explorePrefixFiles

// Models
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../models/igdb_models.dart';

// Providers
import '../providers/prefix_provider.dart';

// Services
import 'log_service.dart';
import 'igdb_service.dart';
import 'process_service.dart';
import 'prefix_management_service.dart'; // Import PrefixManagementService

// Widgets (Import dialogs needed)
import '../widgets/game_details_dialog.dart';
import '../widgets/game_search_dialog.dart';
import '../widgets/common_components_dialog.dart';
import '../widgets/change_prefix_dialog.dart';
import '../widgets/text_input_dialog.dart'; // Import TextInputDialog

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
        _prefixManagementService = prefixManagementService ?? PrefixManagementService();


  // Removed _addLog helper, using _logService.log directly

  /// Handles picking an executable file, asking if it's a game, fetching IGDB data if needed,
  /// and adding it to a prefix via the provider.
  Future<void> addExecutableToPrefix(BuildContext context, WinePrefix prefix) async {
    // Make sure we're using the root navigator context for dialogs
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe', 'msi', 'bat'], // Allow common executable types
      );

      if (result == null || result.files.single.path == null) {
        _logService.log('Executable selection cancelled.');
        return;
      }

      final filePath = result.files.single.path!;
      final fileName = p.basename(filePath);
      final exeName = p.basenameWithoutExtension(fileName);

      // Check if executable already exists in this prefix
      if (_prefixProvider.prefixes.firstWhere((p) => p.path == prefix.path).exeEntries.any((e) => e.path == filePath)) {
         _logService.log('Executable "$fileName" already exists in prefix "${prefix.name}".');
         if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
               SnackBar(content: Text('Executable "$fileName" already exists in this prefix.')),
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
            validator: (value) => (value == null || value.trim().isEmpty) ? 'Name cannot be empty' : null,
          ),
        );

        if (gameNameToSearch == null || gameNameToSearch.isEmpty) {
          _logService.log('IGDB search cancelled or name empty. Adding as game without metadata.');
          finalExeEntry = ExeEntry(path: filePath, name: exeName, isGame: true);
        } else {
          // --- Search IGDB ---
          _logService.log('Searching IGDB for "$gameNameToSearch"...');
          ExeEntry tempEntry = ExeEntry(path: filePath, name: exeName, isGame: true); // Start with basic game entry
          String igdbStatus = "";

          try {
            final tokenData = await _igdbService.getIgdbToken(_settings);
            if (tokenData != null && tokenData['token'] != null) {
              final token = tokenData['token'] as String;
              final searchResults = await _igdbService.searchIgdbGames(gameNameToSearch, _settings, token);

              if (searchResults.isNotEmpty) {
                 // TODO: Potentially show a selection dialog if multiple results?
                 // For now, just take the first result.
                 final IgdbGame firstMatch = searchResults.first;
                 _logService.log('Found IGDB match: ${firstMatch.name} (ID: ${firstMatch.id})');

                 // Fetch details
                 final coverDetails = await _igdbService.fetchCoverDetails(firstMatch.cover, _settings, token);
                 final screenshotDetails = await _igdbService.fetchScreenshotDetails(firstMatch.screenshots, _settings, token);
                 final videoIds = await _igdbService.fetchGameVideoIds(firstMatch.id, _settings, token);

                 // Enrich the entry
                 tempEntry = tempEntry.copyWith(
                   igdbId: firstMatch.id,
                   description: firstMatch.summary,
                   igdbCoverId: firstMatch.cover,
                   coverUrl: coverDetails?['url'],
                   coverImageId: coverDetails?['imageId'],
                   igdbScreenshotIds: firstMatch.screenshots,
                   screenshotUrls: screenshotDetails.map((s) => s['url']!).toList(),
                   screenshotImageIds: screenshotDetails.map((s) => s['imageId']!).toList(),
                   videoIds: videoIds,
                 );
                 igdbStatus = " Found IGDB details.";
              } else {
                 igdbStatus = " No IGDB details found.";
                 _logService.log('No IGDB match found for query: "$gameNameToSearch"');
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
                SnackBar(content: Text('IGDB Fetch: ${igdbStatus.trim()}'), duration: const Duration(seconds: 2)),
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
            SnackBar(content: Text(_prefixProvider.status), duration: const Duration(seconds: 2)),
         );
      }

    } catch (e) {
       _logService.log('Error adding executable: $e', LogLevel.error);
       if (rootContext.mounted) {
          ScaffoldMessenger.of(rootContext).showSnackBar(
             SnackBar(content: Text('Error adding executable: $e'), duration: const Duration(seconds: 3)),
          );
       }
    }
  }

  /// Launches the specified game executable.
  /// Accepts optional callbacks for process start and exit.
  Future<void> launchGame(GameEntry entry, {
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
          onProcessExit?.call(exePath, exitCode, errors); // Call the provided callback
        },
      );
    } catch (e) {
      _logService.log('Error running executable: $e', LogLevel.error);
      // Rethrow the error so the caller can handle UI state reset
      rethrow;
    }
  }

  /// Shows the Game Details Dialog and handles its actions.
  Future<void> showGameDetails(BuildContext scaffoldContext, GameEntry entry) async {
    // Ensure settings are loaded before showing details that might need IGDB
    if (_settings.igdbClientId.isEmpty || _settings.igdbClientSecret.isEmpty) {
       _logService.log('IGDB credentials not set. Cannot fetch full details.', LogLevel.warning); // FIX: Use positional level
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
      builder: (dialogContext) => GameDetailsDialog( // This is the GameDetailsDialog context
        game: entry, // Use 'game' parameter name
        settings: _settings, // Pass settings
        availablePrefixes: availablePrefixes, // Pass available prefixes
        // prefixProvider: _prefixProvider, // Pass provider instance - Removed from GameDetailsDialog
        onLaunchGame: () async { // Adjusted signature to match dialog expectation (VoidCallback)
          // Close dialog before running
          if (Navigator.of(dialogContext).canPop()) {
             Navigator.of(dialogContext).pop();
          }
          // Call the dedicated launch method
          // NOTE: We don't have the HomePage's state callbacks here.
          // Launching from details won't update HomePage's state directly.
          // This might be acceptable, or require further refactoring (e.g., passing callbacks through).
          // For now, just launch without state updates in HomePage.
          await launchGame(entry);
        },
        // onKillProcess: (pid) async { // This callback seems missing from GameDetailsDialog constructor
        //    // Use injected ProcessService instance
        //    final success = await _processService.killProcess(pid);
        //    _logService.log(success ? 'Kill signal sent to PID $pid.' : 'Failed to send kill signal to PID $pid.'); // Use log
        // },
        onEditExePath: (gameEntry) async { // FIX: Rename parameter to onEditExePath
           final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['exe', 'msi', 'bat'],
              initialDirectory: p.dirname(gameEntry.exe.path), // Use gameEntry
           );
           if (result != null && result.files.single.path != null) {
              final newPath = result.files.single.path!;
              // Use injected PrefixProvider instance
              await _prefixProvider.updateExecutablePath(gameEntry.prefix, gameEntry.exe, newPath); // Use gameEntry
              if (Navigator.of(dialogContext).canPop()) {
                 Navigator.of(dialogContext).pop();
              }
           }
        },
        onUpdateMetadata: (gameEntry) async { // Adjusted signature
           _logService.log('Metadata update requested for ${gameEntry.exe.name}'); // Use log
           // Check mount status before showing nested dialog
           if (!scaffoldContext.mounted) return;

           final searchResult = await showDialog<IgdbGame>(
              context: scaffoldContext,
              builder: (_) => GameSearchDialog(
                initialQuery: gameEntry.exe.name, // Use gameEntry
                onSearch: (query) async {
                  // Use injected IgdbService and Settings instances
                  final tokenData = await _igdbService.getIgdbToken(_settings);
                  if (tokenData == null) return {'error': 'Could not get IGDB token'};
                  final games = await _igdbService.searchIgdbGames(query, _settings, tokenData['token']);
                  return {'games': games};
                },
              ),
           );

           // Check mount status again after await
           if (searchResult != null && scaffoldContext.mounted) {
              ExeEntry updatedExe = gameEntry.exe; // Use gameEntry
              _logService.log('Fetching full details for ${searchResult.name} (ID: ${searchResult.id})...'); // Use log
              try {
                 final tokenData = await _igdbService.getIgdbToken(_settings);
                 if (tokenData != null && tokenData['token'] != null) {
                    final token = tokenData['token'] as String;
                    final coverDetails = await _igdbService.fetchCoverDetails(searchResult.cover, _settings, token);
                    // Removed redundant '?? []' as searchResult.screenshots is non-nullable
                    final screenshotDetails = await _igdbService.fetchScreenshotDetails(searchResult.screenshots, _settings, token);
                    final videoIds = await _igdbService.fetchGameVideoIds(searchResult.id, _settings, token);

                    updatedExe = gameEntry.exe.copyWith( // Use gameEntry
                       igdbId: searchResult.id,
                       description: searchResult.summary,
                       igdbCoverId: searchResult.cover,
                       coverUrl: coverDetails?['url'],
                       coverImageId: coverDetails?['imageId'],
                       igdbScreenshotIds: searchResult.screenshots,
                       screenshotUrls: screenshotDetails.map((s) => s['url']!).toList(),
                       screenshotImageIds: screenshotDetails.map((s) => s['imageId']!).toList(),
                       videoIds: videoIds,
                       isGame: true,
                    );
                    _logService.log('Successfully fetched full details for ${searchResult.name}.'); // Use log
                 } else {
                    _logService.log('Could not get IGDB token to fetch full details.', LogLevel.warning); // FIX: Use positional level
                    updatedExe = gameEntry.exe.copyWith(igdbId: searchResult.id); // Use gameEntry
                 }
              } catch (e) {
                 _logService.log('Error fetching full IGDB details: $e. Updating ID only.', LogLevel.error); // FIX: Use positional level
                 updatedExe = gameEntry.exe.copyWith(igdbId: searchResult.id); // Use gameEntry
              }

              // Use injected PrefixProvider instance
              await _prefixProvider.updateExecutable(gameEntry.prefix, updatedExe); // Use gameEntry
              _logService.log('Updated metadata for ${gameEntry.exe.name} from search.'); // Use log

              // Pop the details dialog
              if (Navigator.of(dialogContext).canPop()) {
                 Navigator.of(dialogContext).pop();
              }
           }
        },
        onSaveLaunchOptions: (gameEntry, options) async { // Adjusted signature
           // Use injected PrefixProvider instance
           await _prefixProvider.updateExecutable(gameEntry.prefix, gameEntry.exe.copyWith(launchOptions: options)); // Use gameEntry
           _logService.log('Launch options updated for ${gameEntry.exe.name}.'); // Use log
        },
        // onSaveSteamAppId: (gameEntry, appId) async { // Removed callback
        //    // Use injected PrefixProvider instance
        //    await _prefixProvider.updateExecutable(gameEntry.prefix, gameEntry.exe.copyWith(steamAppId: appId)); // Use gameEntry
        //    _logService.log('Steam App ID updated for ${gameEntry.exe.name}.'); // Use log
        // },
        // Add other required callbacks from GameDetailsDialog constructor
        onChangePrefix: (gameEntry) async { // Adjusted signature and made async
           _logService.log('Change Prefix requested for ${gameEntry.exe.name}');
           // Check mount status before showing nested dialog
           if (!scaffoldContext.mounted) return;

           final selectedDestination = await showDialog<WinePrefix>(
             context: scaffoldContext, // Use the main page context
             builder: (changePrefixDialogContext) => ChangePrefixDialog(
               gameEntry: gameEntry,
               allPrefixes: _prefixProvider.prefixes, // Get all prefixes from provider
               onPrefixSelected: (destinationPrefix) {
                 // This callback is executed when the user confirms in ChangePrefixDialog
                 // We just pop the dialog and return the selected prefix
                 Navigator.of(changePrefixDialogContext).pop(destinationPrefix);
               },
             ),
           );

           // Check mount status again after await
           if (selectedDestination != null && scaffoldContext.mounted) {
             _logService.log('Moving ${gameEntry.exe.name} from ${gameEntry.prefix.name} to ${selectedDestination.name}');
             await _prefixProvider.moveExecutableToPrefix(gameEntry.exe, gameEntry.prefix, selectedDestination);

             // Close the original GameDetailsDialog after moving
             if (Navigator.of(dialogContext).canPop()) {
               Navigator.of(dialogContext).pop();
             }
           } else {
             _logService.log('Change prefix cancelled or failed.');
           }
        },
        // onMoveGameFolder: (gameEntry) async { // Removed callback
        //    // TODO: Implement logic to pick new folder and call provider/service
        //    _logService.log('Move Game Folder requested for ${gameEntry.exe.name}');
        //    // Example: await _prefixProvider.moveGameFolderAndUpdatePath(gameEntry, newParentDir);
        // },
        onToggleWorkingStatus: (gameEntry, isNotWorking) async { // Adjusted signature
           await _prefixProvider.updateExecutable(gameEntry.prefix, gameEntry.exe.copyWith(notWorking: isNotWorking));
           _logService.log('Working status toggled for ${gameEntry.exe.name}');
        },
        onChangeCategory: (gameEntry, category) async { // Adjusted signature
           await _prefixProvider.updateExecutable(gameEntry.prefix, gameEntry.exe.copyWith(category: category));
           _logService.log('Category changed for ${gameEntry.exe.name}');
        },
      ),
    );
  }

  /// Shows the Common Components Dialog.
  Future<void> showCommonComponentsDialog(BuildContext scaffoldContext, WinePrefix prefix) async {
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
  Future<void> runInstallerInPrefix(BuildContext context, WinePrefix prefix) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe', 'msi'],
        dialogTitle: 'Select Installer',
      );

      if (result != null && result.files.single.path != null) {
        final installerPath = result.files.single.path!;
        final installerName = p.basename(installerPath);

        _logService.log('Attempting to run installer "$installerName" in prefix "${prefix.name}"...');

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
            _logService.log('Installer $installerName exited with code $exitCode.');
            if (errors.isNotEmpty) {
              _logService.log('Installer errors:\n${errors.join('\n')}', LogLevel.warning);
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Installer $installerName finished (Code: $exitCode)')),
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
    final uri = Uri.directory(prefix.path);
    _logService.log('Attempting to open prefix directory: ${prefix.path}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _logService.log('Could not launch file explorer for URI: $uri', LogLevel.error);
        // Optionally show error to user
      }
    } catch (e) {
       _logService.log('Error launching file explorer: $e', LogLevel.error);
       // Optionally show error to user
    }
  }

  // Removed showWinetricksVerbsDialog method

}