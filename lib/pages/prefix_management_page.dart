import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Import Provider
import '../models/prefix_models.dart'; // Import the prefix models
import '../models/settings.dart'; // Import Settings model
import '../providers/prefix_provider.dart'; // Import the PrefixProvider
// import '../services/wine_component_installer.dart'; // No longer needed directly here
// import 'package:window_manager/window_manager.dart'; // Temporarily disabled
// import '../providers/window_control_provider.dart'; // No longer needed directly here
import '../widgets/prefix_list_tile.dart'; // Import new widget
import '../widgets/prefix_detail_actions.dart'; // Import new widget
import '../widgets/executable_list_tile.dart'; // Import new widget
import '../widgets/rename_prefix_dialog.dart'; // Import rename dialog


// Define callback types matching PrefixDetailActions expectations
typedef PrefixActionCallback = void Function(WinePrefix prefix);
typedef PrefixContextActionCallback = void Function(BuildContext context, WinePrefix prefix);
// typedef PrefixSettingsActionCallback = void Function(BuildContext context, WinePrefix prefix, Settings settings); // No longer needed for common components
// Keep original typedef for parent compatibility if needed, or refactor parent too
typedef OnExeAction = Future<void> Function(WinePrefix prefix, ExeEntry exe);
// Added callback type for rename from parent
typedef OnRenamePrefixAction = Future<void> Function(BuildContext context, WinePrefix prefix, String newName);


class PrefixManagementPage extends StatefulWidget {
  final Settings? settings;
  final Function(WinePrefix prefix) onAddExecutable; // Use Function type for flexibility if needed, or specific typedef
  // Re-add callbacks needed by children
  final OnExeAction onRunExe;
  final OnExeAction onKillProcess;
  final Map<String, int> runningProcesses;
  final PrefixActionCallback onRunWinetricksGui;
  // final PrefixContextActionCallback onShowWinetricksVerbs; // Removed
  final PrefixContextActionCallback onShowCommonComponents; // Updated signature to use PrefixContextActionCallback
  final PrefixActionCallback onRunInstaller;
  final PrefixActionCallback onExploreHostFiles;
  final Function(BuildContext, WinePrefix) onDeletePrefix; // Keep Function for now
  final Function(BuildContext, WinePrefix, ExeEntry) onDeleteExecutable; // Keep Function for now
  final PrefixContextActionCallback onRunWinecfg; // Re-add
  final OnRenamePrefixAction onRenamePrefix; // Add rename callback parameter
  final PrefixContextActionCallback onApplyControllerFix; // Add controller fix callback
  final PrefixContextActionCallback onEditEnvVariables; // Add environment variables callback
  final PrefixType prefixTypeFilter; // Add prefix type filter parameter

  const PrefixManagementPage({
    Key? key,
    required this.settings,
    required this.onAddExecutable,
    required this.onShowCommonComponents, // Updated signature
    required this.onDeletePrefix,
    required this.onDeleteExecutable,
    required this.onRenamePrefix, // Make rename callback required
    // Add back required parameters
    required this.onRunExe,
    required this.onKillProcess,
    required this.runningProcesses,
    required this.onRunWinetricksGui,
    // required this.onShowWinetricksVerbs, // Removed
    required this.onRunInstaller,
    required this.onExploreHostFiles,
    required this.onRunWinecfg,
    required this.onApplyControllerFix, // Add controller fix parameter
    required this.onEditEnvVariables, // Add environment variables parameter
    required this.prefixTypeFilter, // Make prefix type filter required
  }) : super(key: key);

  @override
  State<PrefixManagementPage> createState() => _PrefixManagementPageState();
}

class _PrefixManagementPageState extends State<PrefixManagementPage> {
  // Removed _localStatus and _logService as they are not used here anymore
  // String _localStatus = '';
  // final LogService _logService = LogService();

  // Helper functions are now passed in via widget callbacks.

  // Helper to show the rename dialog - This now calls the parent's callback directly
  void _showRenameDialog(BuildContext context, WinePrefix prefix) {
     showDialog(
        context: context,
        builder: (dialogContext) => RenamePrefixDialog(
           prefixToRename: prefix,
           onConfirmRename: (newName) {
              // Call the callback passed from the parent (MainScaffold -> ManagePrefixesPage -> this)
              widget.onRenamePrefix(context, prefix, newName);
           },
        ),
     );
  }

  @override
  Widget build(BuildContext context) {
    final prefixProvider = context.watch<PrefixProvider>();
    // Filter the prefixes by type
    final prefixes = prefixProvider.prefixes
        .where((prefix) => prefix.type == widget.prefixTypeFilter)
        .toList();

    return prefixes.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder_off_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text('No ${widget.prefixTypeFilter.name} prefixes found.', style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                const Text('Create a new prefix using the "Create" tab.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          )
        : ListView.builder(
            itemCount: prefixes.length,
            itemBuilder: (context, index) {
              final prefix = prefixes[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                elevation: 2,
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  title: PrefixListTile(prefix: prefix),
                  childrenPadding: EdgeInsets.zero,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            Text('Build: ${prefix.wineBuildPath}', style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 8),
                         ]
                      ),
                    ),
                    PrefixDetailActions( // Pass the rename callback down
                      prefix: prefix,
                      settings: widget.settings,
                      onAddExecutable: widget.onAddExecutable,
                      onShowCommonComponents: widget.onShowCommonComponents,
                      onDeletePrefix: widget.onDeletePrefix,
                      onRenamePrefix: (ctx, pfx) => _showRenameDialog(ctx, pfx), // Use helper to show dialog
                      onRunWinecfg: widget.onRunWinecfg,
                      onRunWinetricksGui: widget.onRunWinetricksGui,
                      onRunInstaller: widget.onRunInstaller,
                      onExploreHostFiles: widget.onExploreHostFiles,
                      onApplyControllerFix: widget.onApplyControllerFix, // Pass controller fix callback
                      onEditEnvVariables: widget.onEditEnvVariables, // Pass environment variables callback
                    ),
                    if (prefix.exeEntries.isNotEmpty) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
                        child: Text('Executables:', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: prefix.exeEntries.length,
                        itemBuilder: (context, exeIndex) {
                          final exe = prefix.exeEntries[exeIndex];
                          // Pass runningProcesses map down to check status
                          final isRunning = widget.runningProcesses.containsKey(exe.path);
                          return ExecutableListTile(
                            prefix: prefix,
                            exe: exe,
                            isRunning: isRunning, // Use actual running status
                            // Pass required callbacks
                            onRunExe: widget.onRunExe,
                            onKillProcess: widget.onKillProcess,
                            onDeleteExe: widget.onDeleteExecutable, // Pass context implicitly
                          );
                        },
                      ),
                       const SizedBox(height: 8),
                    ] else
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                        child: Text('No executables added to this prefix yet.'),
                      ),
                  ],
                ),
              );
            },
          );
  }
}
