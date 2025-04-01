import 'dart:io';
import 'package:flutter/foundation.dart'; // For listEquals, ChangeNotifier, debugPrint
import 'package:path/path.dart' as p;
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../services/prefix_storage_service.dart';
import '../services/prefix_management_service.dart';
import '../services/cover_art_service.dart';

class PrefixProvider with ChangeNotifier {
  List<WinePrefix> _prefixes = [];
  bool _isLoading = false;
  String _status = '';
  Settings? _settings;

  final PrefixStorageService _storageService = PrefixStorageService();
  final PrefixManagementService _managementService = PrefixManagementService();
  final CoverArtService _coverArtService = CoverArtService();
  final PrefixStorageService _prefixStorageService = PrefixStorageService();

  List<WinePrefix> get prefixes => List.unmodifiable(_prefixes);
  bool get isLoading => _isLoading;
  String get status => _status;
  Settings? get settings => _settings;

  void _updateStatus(String message) {
    if (_status != message) {
      _status = message;
      notifyListeners();
    }
    // Removed misplaced debugPrint
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
    // _storageService.updateLibraryPath(newSettings.gameLibraryPath); // Method doesn't exist
    debugPrint("[PrefixProvider] Settings updated. Image Base URL: ${_settings?.igdbImageBaseUrl}");

    notifyListeners();
  }

  Future<void> loadPrefixes() async {
    _setLoading(true, "Loading prefixes...");
    try {
      if (_settings == null) throw Exception("Settings not loaded before loading prefixes.");
      _prefixes = await _storageService.loadPrefixes(_settings!); // Pass Settings
      _updateStatus('Prefixes loaded successfully.');
      await checkAndDownloadMissingImages();
    } catch (e) {
      _updateStatus('Error loading prefixes: $e');
      debugPrint('Error loading prefixes: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> savePrefixes() async {
    if (_settings == null) {
       _updateStatus('Error saving prefixes: Settings not loaded.');
       debugPrint('Error saving prefixes: Settings not loaded.');
       return;
    }
    try {
      await _storageService.savePrefixes(_prefixes, _settings!); // Pass Settings
      debugPrint('Prefixes saved via Provider.');
    } catch (e) {
      _updateStatus('Error saving prefixes: $e');
      debugPrint('Error saving prefixes: $e');
    }
  }

  Future<void> scanForPrefixes() async {
     if (_settings == null) {
       _updateStatus('Cannot scan: Settings not loaded.');
       return;
     }
    _setLoading(true, "Scanning for prefixes...");
    try {
      // Use correct method name and pass Settings
      final scannedPrefixes = await _managementService.scanForExistingPrefixes(_settings!);
      bool updated = false;
      int addedCount = 0;
      List<WinePrefix> currentPrefixes = List.from(_prefixes);

      for (final scannedPrefix in scannedPrefixes) {
        final index = currentPrefixes.indexWhere((p) => p.path == scannedPrefix.path);
        if (index == -1) {
          currentPrefixes.add(scannedPrefix);
          debugPrint('Discovered new prefix via Provider: ${scannedPrefix.name}');
          updated = true;
          addedCount++;
        } else {
           debugPrint('Prefix already known via Provider: ${scannedPrefix.name}');
        }
      }

      if (updated) {
        _prefixes = currentPrefixes;
        _updateStatus('Scan complete. Added $addedCount new prefix(es).');
        await savePrefixes();
        notifyListeners();
      } else {
         _updateStatus('Scan complete. No new prefixes found.');
      }
    } catch (e) {
      _updateStatus('Error scanning for prefixes: $e');
      debugPrint('Error scanning for prefixes: $e');
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
    debugPrint('Attempting to delete prefix (Provider): ${prefixToDelete.name}');
    try {
      // Call the correct method in PrefixManagementService
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
      _updateStatus('Error deleting prefix "${prefixToDelete.name}": $e');
      debugPrint('Error deleting prefix: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addExecutable(WinePrefix prefix, ExeEntry newExe) async {
    final prefixIndex = _prefixes.indexWhere((p) => p.path == prefix.path);
    if (prefixIndex != -1) {
      if (!_prefixes[prefixIndex].exeEntries.any((e) => e.path == newExe.path)) {
        final updatedEntries = List<ExeEntry>.from(_prefixes[prefixIndex].exeEntries)..add(newExe);
        _prefixes[prefixIndex] = _prefixes[prefixIndex].copyWith(exeEntries: updatedEntries);
        _updateStatus('Executable "${newExe.name}" added to prefix "${prefix.name}".');
        await savePrefixes();
        notifyListeners();
        await checkAndDownloadMissingImages(forceCheck: true);
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
           debugPrint('Deleted executable via Provider: ${exeToDelete.path} from prefix: ${prefix.path}');
           await savePrefixes();
           notifyListeners();
        } else {
           _updateStatus('Error deleting executable: Executable not found.');
           debugPrint('Error deleting executable via Provider: ExeEntry not found.');
        }
     } else {
        _updateStatus('Error deleting executable: Prefix not found.');
        debugPrint('Error deleting executable via Provider: Prefix not found.');
     }
  }

  Future<void> updateExecutable(WinePrefix prefix, ExeEntry updatedExe) async {
     final prefixIndex = _prefixes.indexWhere((p) => p.path == prefix.path);
     if (prefixIndex != -1) {
        final exeIndex = _prefixes[prefixIndex].exeEntries.indexWhere((e) => e.path == updatedExe.path);
        if (exeIndex != -1) {
           final updatedEntries = List<ExeEntry>.from(_prefixes[prefixIndex].exeEntries);
           updatedEntries[exeIndex] = updatedExe;
           _prefixes[prefixIndex] = _prefixes[prefixIndex].copyWith(exeEntries: updatedEntries);
           _updateStatus('Executable "${updatedExe.name}" updated.');
           await savePrefixes();
           notifyListeners();
           await checkAndDownloadMissingImages(forceCheck: true);
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
        debugPrint('Error moving executable: $e');
     } finally {
        _setLoading(false);
     }
  }

  Future<void> checkAndDownloadMissingImages({bool forceCheck = false}) async {
    if (_settings == null) {
       debugPrint("Cannot check images: Settings not loaded.");
       return;
    }

    debugPrint("Checking for missing local images (Provider)...");
    bool requiresSave = false;
    int checked = 0;
    int downloadedCovers = 0;
    int downloadedScreenshots = 0;

    List<WinePrefix> updatedPrefixesList = List.from(_prefixes);

    for (int i = 0; i < updatedPrefixesList.length; i++) {
      WinePrefix prefix = updatedPrefixesList[i];
      List<ExeEntry> updatedEntries = List.from(prefix.exeEntries);
      bool prefixUpdated = false;

      for (int j = 0; j < updatedEntries.length; j++) {
        ExeEntry entry = updatedEntries[j];
        checked++;
        ExeEntry currentUpdatedEntry = entry;
        bool entryUpdated = false;

        bool coverMissing = entry.igdbId != null && entry.coverUrl != null && entry.coverUrl!.isNotEmpty && (entry.localCoverPath == null || entry.localCoverPath!.isEmpty);
        bool screenshotsMissing = entry.screenshotUrls.isNotEmpty && (entry.localScreenshotPaths.isEmpty || entry.localScreenshotPaths.length != entry.screenshotUrls.length);

        // --- Cover Reconstruction & Check ---
        String? coverUrlToCheck = entry.coverUrl;
        if (entry.coverImageId != null && entry.coverImageId!.isNotEmpty &&
            (_settings != null && (coverUrlToCheck == null || coverUrlToCheck.isEmpty || coverUrlToCheck.startsWith('https://api.igdb.com')))) {
           debugPrint("Reconstructing cover URL for ${entry.name} using image ID ${entry.coverImageId}");
           coverUrlToCheck = '${_settings!.igdbImageBaseUrl}/t_cover_big/${entry.coverImageId}.jpg';
    debugPrint("[checkAndDownloadMissingImages] Using Image Base URL: ${_settings?.igdbImageBaseUrl}");

           currentUpdatedEntry = currentUpdatedEntry.copyWith(coverUrl: coverUrlToCheck);
           entryUpdated = true;
           // Explicitly update entry as well, just in case
           entry = currentUpdatedEntry;
        }

        if ((forceCheck || coverMissing) && entry.igdbId != null && coverUrlToCheck != null && coverUrlToCheck.isNotEmpty) {
           debugPrint("Checking/Downloading cover for ${entry.name} (${entry.igdbId}) from $coverUrlToCheck");
           final localPath = await _coverArtService.getLocalCoverPath(entry.igdbId!, coverUrlToCheck);
           if (localPath != null && localPath != entry.localCoverPath) {
              currentUpdatedEntry = currentUpdatedEntry.copyWith(localCoverPath: localPath);
              if (coverMissing) downloadedCovers++;
              requiresSave = true;
              entryUpdated = true;
           }
        }

        // --- Screenshot Reconstruction Check ---
        List<String> screenshotUrlsToCheck = List.from(currentUpdatedEntry.screenshotUrls);
           debugPrint("  >> Settings Image Base URL: ${_settings?.igdbImageBaseUrl}");
           debugPrint("  >> Cover Image ID: ${entry.coverImageId}");

        bool reconstructedScreenshots = false;
        if (currentUpdatedEntry.screenshotImageIds.isNotEmpty && _settings != null &&
            // Removed misplaced debugPrint statement here
            (screenshotUrlsToCheck.isEmpty || screenshotUrlsToCheck.length != currentUpdatedEntry.screenshotImageIds.length || (screenshotUrlsToCheck.isNotEmpty && screenshotUrlsToCheck.first.startsWith('https://api.igdb.com')))) {
           debugPrint("Reconstructing screenshot URLs for ${currentUpdatedEntry.name} using image IDs");
           screenshotUrlsToCheck = currentUpdatedEntry.screenshotImageIds
               .map((id) => '${_settings!.igdbImageBaseUrl}/t_screenshot_big/$id.jpg')
               .toList();
           reconstructedScreenshots = true;
           currentUpdatedEntry = currentUpdatedEntry.copyWith(screenshotUrls: screenshotUrlsToCheck);
           entryUpdated = true;
           // Explicitly update entry as well, just in case
           entry = currentUpdatedEntry;
        }

        // --- Screenshot Download Check ---
        if ((forceCheck || screenshotsMissing || reconstructedScreenshots) && screenshotUrlsToCheck.isNotEmpty) {
           debugPrint("Checking/Downloading screenshots for ${currentUpdatedEntry.name}...");
           final localPaths = await _coverArtService.getLocalScreenshotPaths(screenshotUrlsToCheck);
           if (localPaths.isNotEmpty && !_listEquals(localPaths, currentUpdatedEntry.localScreenshotPaths)) {
                 currentUpdatedEntry = currentUpdatedEntry.copyWith(localScreenshotPaths: localPaths);
                 if (screenshotsMissing) downloadedScreenshots += localPaths.length;
                 requiresSave = true;
                 entryUpdated = true;
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

    debugPrint("Image check complete."); // Further simplified

    if (requiresSave) {
      debugPrint("Saving updated prefix data with new local image paths (Provider)...");
      _prefixes = updatedPrefixesList;
      _updateStatus("Downloaded/Verified missing images.");
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
      debugPrint('Successfully moved folder and updated path for "${gameEntry.exe.name}".');
    } catch (e) {
      _updateStatus('Error moving game folder: $e');
      debugPrint('Error moving game folder (Provider): $e');
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
        throw Exception('The selected file does not exist.');
      }
      
      // Create updated entry with new path
      final updatedExe = exeEntry.copyWith(path: newPath);
      
      // Find prefix and exe indexes
      final prefixIndex = _prefixes.indexWhere((p) => p.path == prefix.path);
      if (prefixIndex == -1) {
        throw Exception('Prefix not found.');
      }
      
      final exeIndex = _prefixes[prefixIndex].exeEntries.indexWhere((e) => e.path == exeEntry.path);
      if (exeIndex == -1) {
        throw Exception('Executable not found in prefix.');
      }
      
      // Update the exe entry
      final updatedPrefixes = List<WinePrefix>.from(_prefixes);
      final updatedExeEntries = List<ExeEntry>.from(updatedPrefixes[prefixIndex].exeEntries);
      updatedExeEntries[exeIndex] = updatedExe;
      
      updatedPrefixes[prefixIndex] = updatedPrefixes[prefixIndex].copyWith(exeEntries: updatedExeEntries);
      
      // Update state
      _prefixes = updatedPrefixes;
      _status = 'Executable path updated successfully.';
      notifyListeners();
      
      // Save changes
      await _prefixStorageService.savePrefixes(_prefixes, _settings!);
    } catch (e) {
      _status = 'Error updating executable path: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _savePrefixes() async {
    try {
      if (_settings == null) {
        _status = 'Error saving prefixes: Settings not initialized';
        print(_status);
        return;
      }
      
      // Pass _settings (now guaranteed non-null) to savePrefixes
      await _prefixStorageService.savePrefixes(_prefixes, _settings!);
      
      notifyListeners();
    } catch (e) {
      _status = 'Error saving prefixes: $e';
      print(_status);
    }
  }
}