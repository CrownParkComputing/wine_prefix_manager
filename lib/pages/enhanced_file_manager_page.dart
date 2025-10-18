import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/prefix_models.dart';
import '../providers/prefix_provider.dart';
import '../widgets/dual_pane_file_manager.dart';

class EnhancedFileManagerPage extends StatelessWidget {
  final GameEntry? game;

  const EnhancedFileManagerPage({super.key, this.game});

  @override
  Widget build(BuildContext context) {
    final prefixProvider = context.watch<PrefixProvider>();
    
    // Build list of all games for the file manager
    final List<GameEntry> allGames = [];
    for (final prefix in prefixProvider.prefixes) {
      for (final exe in prefix.exeEntries) {
        allGames.add(GameEntry(prefix: prefix, exe: exe));
      }
    }
    
    return DualPaneFileManager(
      initialLeftPath: game?.prefix.path,
      gameEntries: allGames,
      onAddToGameLibrary: (exePath) => _addExecutableToGameLibrary(context, exePath, prefixProvider),
      onUpdateGamePath: (oldPath, newPath) => _updateGameExecutablePath(context, oldPath, newPath, prefixProvider),
    );
  }
  
  void _addExecutableToGameLibrary(BuildContext context, String exePath, PrefixProvider prefixProvider) async {
    try {
      // Find which prefix this executable belongs to
      WinePrefix? targetPrefix;
      for (final prefix in prefixProvider.prefixes) {
        if (exePath.startsWith(prefix.path)) {
          targetPrefix = prefix;
          break;
        }
      }
      
      if (targetPrefix == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not determine which prefix this executable belongs to')),
          );
        }
        return;
      }
      
      // Check if executable already exists in library
      final existingExe = targetPrefix.exeEntries.where((exe) => exe.path == exePath).isNotEmpty;
      
      if (existingExe) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Executable is already in the game library')),
          );
        }
        return;
      }
      
      // Create new executable entry
      final fileName = exePath.split('/').last.replaceAll('.exe', '');
      final newExe = ExeEntry(
        name: fileName,
        path: exePath,
        isGame: true,
      );
      
      // Add to prefix
      final updatedPrefix = targetPrefix.copyWith(
        exeEntries: [...targetPrefix.exeEntries, newExe],
      );
      
      await prefixProvider.updatePrefix(updatedPrefix);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "$fileName" to game library')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add executable to game library: $e')),
        );
      }
    }
  }
  
  void _updateGameExecutablePath(BuildContext context, String oldPath, String newPath, PrefixProvider prefixProvider) async {
    try {
      // Find the executable entry with the old path
      WinePrefix? targetPrefix;
      ExeEntry? targetExe;
      
      for (final prefix in prefixProvider.prefixes) {
        for (final exe in prefix.exeEntries) {
          if (exe.path == oldPath) {
            targetPrefix = prefix;
            targetExe = exe;
            break;
          }
        }
        if (targetExe != null) break;
      }
      
      if (targetPrefix == null || targetExe == null) {
        return; // No game executable found with old path
      }
      
      // Update the executable path
      final updatedExe = targetExe.copyWith(path: newPath);
      await prefixProvider.updateExecutable(targetPrefix, updatedExe);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated game executable path for "${targetExe.name}"')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update game executable path: $e')),
        );
      }
    }
  }
}