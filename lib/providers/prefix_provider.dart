import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; // For listEquals, ChangeNotifier, debugPrint
import 'package:path/path.dart' as p; // Import path package
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../services/prefix_storage_service.dart';
import '../services/prefix_management_service.dart';
import '../services/cover_art_service.dart';
import '../services/igdb_service.dart'; // Import IgdbService
import '../models/igdb_models.dart'; // Import IgdbGame model

class PrefixProvider with ChangeNotifier {
  List<WinePrefix> _prefixes = [];
  bool _isLoading = false;
  String _status = '';
  Settings? _settings;

  final PrefixStorageService _storageService = PrefixStorageService();
  final PrefixManagementService _managementService = PrefixManagementService();
  final CoverArtService _coverArtService = CoverArtService();
  final PrefixStorageService _prefixStorageService = PrefixStorageService();
  final IgdbService _igdbService = IgdbService(); // Add IgdbService instance

  List<WinePrefix> get prefixes => List.unmodifiable(_prefixes);
  bool get isLoading => _isLoading;
  String get status => _status;
  Settings? get settings => _settings;

  void _updateStatus(String message) {
    if (_status != message) {
      _status = message;
      notifyListeners();
    }
  }

  void _setLoading(bool loading, [String statusMessage = '']) {
    bool changed = false;
    if (_isLoading != loading) {
      _isLoading = loading;
      changed = true;
    }
    if (statusMessage.isNotEmpty || !loading) {
       if (_status != statusMessage) {
         _status = statusMessage;
         changed = true;
       }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void updateSettings(Settings newSettings) {
    _settings = newSettings;
    // debugPrint("[PrefixProvider] Settings updated. Image Base URL: ${_settings.igdbImageBaseUrl}"); // Removed ?.
    notifyListeners();
  }

  Future<void> loadPrefixes({bool forceReload = false}) async {
    if (_isLoading && !forceReload) {
      // Return early if already loading and not a forced reload
      return;
    }
    
    _setLoading(true, forceReload ? "Refreshing prefixes..." : "Loading prefixes...");
    try {
      if (_settings == null) throw Exception("Settings not loaded before loading prefixes.");
      List<WinePrefix> loadedPrefixes = await _storageService.loadPrefixes(_settings!);

      bool prefixesUpdated = false;
      List<WinePrefix> checkedPrefixes = [];
      for (final prefix in loadedPrefixes) {
        List<ExeEntry> updatedEntries = [];
        bool prefixChanged = false;
        for (final exe in prefix.exeEntries) {
          final fileExists = await File(exe.path).exists();
          if (!fileExists && !exe.notWorking) {
            // debugPrint('Executable not found, marking as not working: ${exe.path}');
            updatedEntries.add(exe.copyWith(notWorking: true));
            prefixChanged = true;
            prefixesUpdated = true;
          } else {
            updatedEntries.add(exe);
          }
        }
        if (prefixChanged) {
          checkedPrefixes.add(prefix.copyWith(exeEntries: updatedEntries));
        } else {
          checkedPrefixes.add(prefix);
        }
      }

      _prefixes = checkedPrefixes;

      if (prefixesUpdated) {
        _updateStatus('Prefixes loaded. Some executables marked as not working (file not found).');
        await savePrefixes();
      } else {
        _updateStatus('Prefixes loaded successfully.');
      }

      await checkAndDownloadMissingImages(); // Check images after loading
    } catch (e) {
      _updateStatus('Error loading prefixes: $e');
      // debugPrint('Error loading prefixes: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> savePrefixes() async {
    if (_settings == null) {
       _updateStatus('Error saving prefixes: Settings not loaded.');
       // debugPrint('Error saving prefixes: Settings not loaded.');
       return;
    }
    try {
      await _storageService.savePrefixes(_prefixes, _settings!);
      // debugPrint('Prefixes saved via Provider.');
    } catch (e) {
      _updateStatus('Error saving prefixes: $e');
      // debugPrint('Error saving prefixes: $e');
    }
  }

  Future<void> scanForPrefixes() async {
     if (_settings == null) {
       _updateStatus('Cannot scan: Settings not loaded.');
       return;
     }
    _setLoading(true, "Scanning for prefixes...");
    try {
      final scannedPrefixes = await _managementService.scanForPrefixes(_settings!);
      bool updated = false;
      int addedCount = 0;
      List<WinePrefix> currentPrefixes = List.from(_prefixes); // Makes a copy

      for (final scannedPrefix in scannedPrefixes) {
        final index = currentPrefixes.indexWhere((p) => p.path == scannedPrefix.path);
        if (index == -1) { // <-- Only adds if NOT found
          currentPrefixes.add(scannedPrefix);
          // debugPrint('Discovered new prefix via Provider: ${scannedPrefix.name}');
          updated = true;
          addedCount++;
        } else { // Prefix already exists, check if it needs updating
          // Compare relevant fields (e.g., type, buildPath)
          // Note: We don't compare exeEntries here as the scanner doesn't load them.
          if (currentPrefixes[index].type != scannedPrefix.type ||
              currentPrefixes[index].wineBuildPath != scannedPrefix.wineBuildPath) {
            // debugPrint('Updating existing prefix via Provider: ${scannedPrefix.name} (Type: ${currentPrefixes[index].type.name} -> ${scannedPrefix.type.name}, BuildPath: ${currentPrefixes[index].wineBuildPath} -> ${scannedPrefix.wineBuildPath})');
            currentPrefixes[index] = scannedPrefix.copyWith(exeEntries: currentPrefixes[index].exeEntries); // Keep existing exeEntries
            updated = true; // Mark as updated even if no new prefixes were added
          } else {
            // debugPrint('Prefix already known and up-to-date via Provider: ${scannedPrefix.name}');
          }
        }
      }

      if (updated) {
        _prefixes = currentPrefixes; // Only updates _prefixes if a NEW prefix was added or an existing one changed
        _updateStatus('Scan complete. $addedCount new prefix(es) added/updated.'); // Updated status message
        await savePrefixes();
        notifyListeners();
      } else {
         _updateStatus('Scan complete. No new or changed prefixes found.'); // Updated status message
      }
    } catch (e) {
      _updateStatus('Error scanning for prefixes: $e');
      // debugPrint('Error scanning for prefixes: $e');
    } finally {
      _setLoading(false);
    }
  }

  void addCreatedPrefix(WinePrefix newPrefix) {
     if (!_prefixes.any((p) => p.path == newPrefix.path)) {
        _prefixes.add(newPrefix);
        _updateStatus('Prefix "${newPrefix.name}" added successfully.');
        savePrefixes();
        notifyListeners();
     } else {
        _updateStatus('Prefix "${newPrefix.name}" already exists.');
     }
  }

  Future<void> deletePrefix(WinePrefix prefixToDelete) async {
    _setLoading(true, 'Deleting prefix "${prefixToDelete.name}"...');
    // debugPrint('Attempting to delete prefix (Provider): ${prefixToDelete.name}');
    try {
      final success = await _managementService.deletePrefixDirectory(prefixToDelete.path);
      if (success) {
        _prefixes.removeWhere((p) => p.path == prefixToDelete.path);
        _updateStatus('Prefix "${prefixToDelete.name}" deleted successfully.');
        await savePrefixes();
        notifyListeners();
      } else {
        _updateStatus('Failed to delete prefix directory for "${prefixToDelete.name}". Prefix not removed from list.');
      }
    } catch (e) {
      _updateStatus('Error deleting prefix: $e');
      // debugPrint('Error deleting prefix: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> renamePrefix(WinePrefix prefixToRename, String newName) async {
    _setLoading(true, 'Renaming prefix "${prefixToRename.name}" to "$newName"...');
    try {
      // 1. Rename the directory
      final newPath = await _managementService.renamePrefixDirectory(prefixToRename.path, newName);

      // 2. Find the prefix in the list
      final prefixIndex = _prefixes.indexWhere((p) => p.path == prefixToRename.path);
      if (prefixIndex == -1) {
        throw Exception('Prefix not found in provider state after renaming directory.');
      }

      // 3. Update ExeEntry paths within the prefix
      final List<ExeEntry> updatedExeEntries = _prefixes[prefixIndex].exeEntries.map((exe) {
        // Assuming exe paths are relative to the prefix directory's parent is incorrect.
        // Exe paths are usually absolute. Renaming the prefix directory *should not*
        // require updating absolute executable paths within it.
        // If paths *were* relative, we'd need complex logic. Sticking with absolute paths.
        // String relativePath = p.relative(exe.path, from: prefixToRename.path);
        // String newExePath = p.join(newPath, relativePath);
        // return exe.copyWith(path: newExePath);
        return exe; // Keep original absolute path
      }).toList();

      // 4. Update the prefix object in the list
      _prefixes[prefixIndex] = _prefixes[prefixIndex].copyWith(
        name: newName,
        path: newPath,
        exeEntries: updatedExeEntries,
      );

      // 5. Save and notify
      _updateStatus('Prefix renamed to "$newName" successfully.');
      await savePrefixes();
      notifyListeners();

    } catch (e) {
      _updateStatus('Error renaming prefix: $e');
      // Re-throw the exception so the dialog can display it
      rethrow;
    } finally {
      _setLoading(false);
    }
  }


  /// Adds a pre-constructed ExeEntry to a prefix.
  /// Assumes IGDB fetching/user confirmation has already happened.
  Future<void> addExecutable(WinePrefix prefix, ExeEntry exeToAdd) async {
    final prefixIndex = _prefixes.indexWhere((p) => p.path == prefix.path);
    if (prefixIndex != -1) {
      if (!_prefixes[prefixIndex].exeEntries.any((e) => e.path == exeToAdd.path)) {
        // Check file existence before adding
        final fileExists = await File(exeToAdd.path).exists();
        ExeEntry finalEntry = exeToAdd;
        if (!fileExists) {
          finalEntry = exeToAdd.copyWith(notWorking: true);
        }

        final updatedEntries = List<ExeEntry>.from(_prefixes[prefixIndex].exeEntries)..add(finalEntry);
        _prefixes[prefixIndex] = _prefixes[prefixIndex].copyWith(exeEntries: updatedEntries);
        _updateStatus('Executable "${finalEntry.name}" added to prefix "${prefix.name}".${!fileExists ? " (Marked as not working)" : ""}');
        await savePrefixes();
        notifyListeners();

        // Trigger image download if URLs were added
        if (finalEntry.coverUrl != null || finalEntry.screenshotUrls.isNotEmpty) {
           await checkAndDownloadMissingImages(forceCheck: true);
        }
      } else {
         _updateStatus('Executable already exists in prefix "${prefix.name}".');
      }
    } else {
       _updateStatus('Error adding executable: Prefix "${prefix.name}" not found.');
    }
  }


  Future<void> deleteExecutable(WinePrefix prefix, ExeEntry exeToDelete) async {
     final prefixIndex = _prefixes.indexWhere((p) => p.path == prefix.path);
     if (prefixIndex != -1) {
        final updatedEntries = List<ExeEntry>.from(_prefixes[prefixIndex].exeEntries)
          ..removeWhere((e) => e.path == exeToDelete.path);
        if (updatedEntries.length < _prefixes[prefixIndex].exeEntries.length) {
           _prefixes[prefixIndex] = _prefixes[prefixIndex].copyWith(exeEntries: updatedEntries);
           _updateStatus('Executable "${exeToDelete.name}" deleted.');
           // debugPrint('Deleted executable via Provider: ${exeToDelete.path} from prefix: ${prefix.path}');
           await savePrefixes();
           notifyListeners();
        } else {
           _updateStatus('Error deleting executable: Executable not found.');
           // debugPrint('Error deleting executable via Provider: ExeEntry not found.');
        }
     } else {
        _updateStatus('Error deleting executable: Prefix not found.');
        // debugPrint('Error deleting executable via Provider: Prefix not found.');
     }
  }

  Future<void> updateExecutable(WinePrefix prefix, ExeEntry updatedExe) async {
     final prefixIndex = _prefixes.indexWhere((p) => p.path == prefix.path);
     if (prefixIndex != -1) {
        final exeIndex = _prefixes[prefixIndex].exeEntries.indexWhere((e) => e.path == updatedExe.path);
        if (exeIndex != -1) {
           // Removed file existence check that overrode notWorking status
           // The updatedExe passed in now directly reflects the user's choice

           final updatedEntries = List<ExeEntry>.from(_prefixes[prefixIndex].exeEntries);
           updatedEntries[exeIndex] = updatedExe; // Use the passed-in updatedExe directly
           _prefixes[prefixIndex] = _prefixes[prefixIndex].copyWith(exeEntries: updatedEntries);
           _updateStatus('Executable "${updatedExe.name}" updated.'); // Simplified status message
           await savePrefixes();
           notifyListeners();
           // Trigger image download check if URLs are present
           if (updatedExe.coverUrl != null || updatedExe.screenshotUrls.isNotEmpty) {
             await checkAndDownloadMissingImages(forceCheck: true); // Use forceCheck to ensure download attempt
           }
        } else {
           _updateStatus('Error updating executable: Executable not found.');
        }
     } else {
        _updateStatus('Error updating executable: Prefix not found.');
     }
  }

  Future<void> moveExecutableToPrefix(ExeEntry exeToMove, WinePrefix sourcePrefix, WinePrefix destinationPrefix) async {
     _setLoading(true, 'Moving "${exeToMove.name}" to "${destinationPrefix.name}"...');
     try {
        final sourceIndex = _prefixes.indexWhere((p) => p.path == sourcePrefix.path);
        final destIndex = _prefixes.indexWhere((p) => p.path == destinationPrefix.path);
        if (sourceIndex == -1 || destIndex == -1) throw Exception('Source or destination prefix not found.');
        if (_prefixes[destIndex].exeEntries.any((e) => e.path == exeToMove.path)) throw Exception('Executable already exists in destination prefix.');

        final sourceEntries = List<ExeEntry>.from(_prefixes[sourceIndex].exeEntries)..removeWhere((e) => e.path == exeToMove.path);
        final destEntries = List<ExeEntry>.from(_prefixes[destIndex].exeEntries)..add(exeToMove);

        _prefixes[sourceIndex] = _prefixes[sourceIndex].copyWith(exeEntries: sourceEntries);
        _prefixes[destIndex] = _prefixes[destIndex].copyWith(exeEntries: destEntries);

        _updateStatus('Moved "${exeToMove.name}" to "${destinationPrefix.name}".');
        await savePrefixes();
        notifyListeners();
     } catch (e) {
        _updateStatus('Error moving executable: $e');
        // debugPrint('Error moving executable: $e');
     } finally {
        _setLoading(false);
     }
  }

  // Modified: Simplified to only download based on existing URLs
  Future<void> checkAndDownloadMissingImages({bool forceCheck = false}) async {
    if (_settings == null) { // Removed token check as it's not needed for download only
       // debugPrint("[checkAndDownloadMissingImages] Cannot check images: Settings not loaded.");
       return;
    }

    // debugPrint("[checkAndDownloadMissingImages] Starting check for missing local images (forceCheck: $forceCheck)...");
    bool requiresSave = false;
    // Removed fetchedCovers/fetchedScreenshots counters
    int downloadedCovers = 0;
    int downloadedScreenshots = 0;

    List<WinePrefix> updatedPrefixesList = List.from(_prefixes);
    // Removed token variable

    for (int i = 0; i < updatedPrefixesList.length; i++) {
      WinePrefix prefix = updatedPrefixesList[i];
      List<ExeEntry> updatedEntries = List.from(prefix.exeEntries);
      bool prefixUpdated = false;

      for (int j = 0; j < updatedEntries.length; j++) {
        ExeEntry entry = updatedEntries[j];
        ExeEntry currentUpdatedEntry = entry;
        bool entryUpdated = false;
        // debugPrint("[checkAndDownloadMissingImages] Checking entry: ${entry.name} (IGDB ID: ${entry.igdbId})");

        // --- Removed Fetch Cover/Screenshot Details logic ---

        // --- Download Cover Image if needed ---
        bool coverMissingLocally = entry.igdbId != null &&
                                   entry.coverUrl != null &&
                                   entry.coverUrl!.isNotEmpty &&
                                   (entry.localCoverPath == null || entry.localCoverPath!.isEmpty);
        bool shouldDownloadCover = (forceCheck || coverMissingLocally) && entry.igdbId != null && entry.coverUrl != null && entry.coverUrl!.isNotEmpty;
        // debugPrint("[checkAndDownloadMissingImages] Should download cover? $shouldDownloadCover (MissingLocally: $coverMissingLocally, URL: ${entry.coverUrl}, Force: $forceCheck)");

        if (shouldDownloadCover) {
           // debugPrint("[checkAndDownloadMissingImages] Checking/Downloading cover for ${entry.name} (${entry.igdbId}) from ${entry.coverUrl}");
           final localPath = await _coverArtService.getLocalCoverPath(entry.igdbId!, entry.coverUrl!);
           if (localPath != null && localPath != entry.localCoverPath) {
              // debugPrint("[checkAndDownloadMissingImages] Downloaded/Verified cover at: $localPath");
              currentUpdatedEntry = currentUpdatedEntry.copyWith(localCoverPath: localPath);
              if (coverMissingLocally) downloadedCovers++;
              requiresSave = true;
              entryUpdated = true;
           } else if (localPath != null) {
              // debugPrint("[checkAndDownloadMissingImages] Cover already exists locally: $localPath");
           } else {
              // debugPrint("[checkAndDownloadMissingImages] Failed to download/verify cover for ${entry.name}");
           }
        }

        // --- Download Screenshot Images if needed ---
        bool screenshotsMissingLocally = entry.screenshotUrls.isNotEmpty &&
                                         (entry.localScreenshotPaths.isEmpty || entry.localScreenshotPaths.length != entry.screenshotUrls.length);
        bool shouldDownloadScreenshots = (forceCheck || screenshotsMissingLocally) && entry.screenshotUrls.isNotEmpty;
        // debugPrint("[checkAndDownloadMissingImages] Should download screenshots? $shouldDownloadScreenshots (MissingLocally: $screenshotsMissingLocally, URLs: ${entry.screenshotUrls.length}, Force: $forceCheck)");

        if (shouldDownloadScreenshots) {
           // debugPrint("[checkAndDownloadMissingImages] Checking/Downloading ${entry.screenshotUrls.length} screenshots for ${entry.name}...");
           final localPaths = await _coverArtService.getLocalScreenshotPaths(entry.screenshotUrls);
           if (localPaths.isNotEmpty && !_listEquals(localPaths, entry.localScreenshotPaths)) {
                 // debugPrint("[checkAndDownloadMissingImages] Downloaded/Verified ${localPaths.length} screenshots.");
                 currentUpdatedEntry = currentUpdatedEntry.copyWith(localScreenshotPaths: localPaths);
                 if (screenshotsMissingLocally) downloadedScreenshots += localPaths.length;
                 requiresSave = true;
                 entryUpdated = true;
              } else if (localPaths.isNotEmpty) {
                 // debugPrint("[checkAndDownloadMissingImages] Screenshots already exist locally.");
              } else {
                 // debugPrint("[checkAndDownloadMissingImages] Failed to download/verify screenshots for ${entry.name}");
              }
           }

        if (entryUpdated) {
           updatedEntries[j] = currentUpdatedEntry;
           prefixUpdated = true;
        }
      } // End inner loop

      if (prefixUpdated) {
        updatedPrefixesList[i] = prefix.copyWith(exeEntries: updatedEntries);
      }
    } // End outer loop

    // debugPrint("[checkAndDownloadMissingImages] Image download check complete. Downloaded: $downloadedCovers covers, $downloadedScreenshots screenshots.");

    if (requiresSave) {
      // debugPrint("[checkAndDownloadMissingImages] Saving updated prefix data with new local image paths (Provider)...");
      _prefixes = updatedPrefixesList;
      _updateStatus("Downloaded/Verified missing images."); // Keep status generic
      notifyListeners();
      await savePrefixes();
    }
  }


  bool _listEquals<T>(List<T>? a, List<T>? b) {
    return listEquals(a, b); // Use foundation's listEquals
  }

  Future<void> moveGameFolderAndUpdatePath(GameEntry gameEntry, String destinationParentDir) async {
    _setLoading(true, 'Moving folder for "${gameEntry.exe.name}"...');
    try {
      // Ensure PrefixManagementService has this method signature
      final updatedExePath = await _managementService.moveGameFolder(gameEntry.exe.path, destinationParentDir);
      final updatedExe = gameEntry.exe.copyWith(path: updatedExePath);
      await updateExecutable(gameEntry.prefix, updatedExe);
      _updateStatus('Successfully moved folder and updated path for "${gameEntry.exe.name}".');
      // debugPrint('Successfully moved folder and updated path for "${gameEntry.exe.name}".');
    } catch (e) {
      _updateStatus('Error moving game folder: $e');
      // debugPrint('Error moving game folder (Provider): $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Updates an executable's path in a prefix
  Future<void> updateExecutablePath(WinePrefix prefix, ExeEntry exeEntry, String newPath) async {
    try {
      _status = 'Updating executable path...';
      notifyListeners();

      // Check if file exists
      final file = File(newPath);
      if (!await file.exists()) {
        throw Exception('New executable path does not exist: $newPath');
      }

      final prefixIndex = _prefixes.indexWhere((p) => p.path == prefix.path);
      if (prefixIndex == -1) {
        throw Exception('Prefix not found');
      }

      final exeIndex = _prefixes[prefixIndex].exeEntries.indexWhere((e) => e.path == exeEntry.path);
      if (exeIndex == -1) {
        throw Exception('Executable not found in prefix');
      }

      // Create updated executable entry
      final updatedExe = exeEntry.copyWith(path: newPath);

      // Update the list
      final updatedEntries = List<ExeEntry>.from(_prefixes[prefixIndex].exeEntries);
      updatedEntries[exeIndex] = updatedExe;
      _prefixes[prefixIndex] = _prefixes[prefixIndex].copyWith(exeEntries: updatedEntries);

      _status = 'Executable path updated successfully.';
      await savePrefixes();
      notifyListeners();
    } catch (e) {
      _status = 'Error updating executable path: $e';
      notifyListeners();
      // Optionally rethrow or handle more gracefully
    }
  }

  // Fix this method to properly create GameEntry objects for all executables
  List<GameEntry> getAllGamesFromPrefixes() {
    final allGames = <GameEntry>[];
    
    for (final prefix in _prefixes) {
      // For each executable in the prefix, create a GameEntry
      for (final exe in prefix.exeEntries) {
        allGames.add(GameEntry(prefix: prefix, exe: exe));
      }
    }
    
    return allGames;
  }

  /// Updates the prefix with new values
  Future<void> updatePrefix(WinePrefix updatedPrefix) async {
    try {
      final index = _prefixes.indexWhere((p) => p.path == updatedPrefix.path);
      if (index != -1) {
        _prefixes[index] = updatedPrefix;
        _updateStatus('Prefix "${updatedPrefix.name}" updated successfully.');
        await savePrefixes();
        notifyListeners();
      } else {
        _updateStatus('Prefix not found for updating.');
      }
    } catch (e) {
      _updateStatus('Error updating prefix: $e');
      // debugPrint('Error updating prefix: $e');
    }
  }
}