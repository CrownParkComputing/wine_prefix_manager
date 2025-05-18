import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../pages/prefix_management_page.dart'; // Import the refactored page
import '../widgets/prefix_creation_form.dart'; // Import the original form widget
import '../widgets/prefix_creation_form_for_type.dart'; // Import the type-specific form widget

// Define callback types needed by child widgets, to be passed from main.dart
typedef OnExeAction = Future<void> Function(WinePrefix prefix, ExeEntry exe);
typedef OnPrefixAction = Future<void> Function(WinePrefix prefix);
typedef OnPrefixContextAction = Future<void> Function(BuildContext context, WinePrefix prefix); // For actions needing context
// Removed Settings from onShowCommonComponents callback type
typedef OnShowDialogAction = Future<void> Function(BuildContext context, WinePrefix prefix);
// Added callback type for rename
typedef OnRenamePrefixAction = Future<void> Function(BuildContext context, WinePrefix prefix, String newName);


class ManagePrefixesPage extends StatefulWidget {
  // Pass all necessary callbacks and data down from main.dart
  final Settings? settings;
  final OnPrefixAction onAddExecutable;
  // Re-add callbacks needed by child widgets
  final OnExeAction onRunExe;
  final OnExeAction onKillProcess;
  final Map<String, int> runningProcesses; // Needed by ExecutableListTile via PrefixManagementPage
  final OnPrefixAction onRunWinetricksGui;
  final OnShowDialogAction onShowCommonComponents; // Updated signature
  final OnPrefixAction onRunInstaller;
  final OnPrefixAction onExploreHostFiles;
  final Function(BuildContext, WinePrefix) onDeletePrefix; // Keep delete actions for now
  final Function(BuildContext, WinePrefix, ExeEntry) onDeleteExecutable; // Keep delete actions for now
  final OnPrefixContextAction onRunWinecfg; // Re-add
  final OnRenamePrefixAction onRenamePrefix; // Add rename callback
  final OnPrefixContextAction onApplyControllerFix; // Add controller fix callback
  final OnPrefixContextAction onEditEnvVariables; // Add environment variables callback

  // Constructor updated to include necessary callbacks again
  const ManagePrefixesPage({
    Key? key,
    required this.settings,
    required this.onAddExecutable,
    required this.onShowCommonComponents, // Updated signature
    required this.onDeletePrefix,
    required this.onDeleteExecutable,
    // Add back required parameters needed by children
    required this.onRunExe,
    required this.onKillProcess,
    required this.runningProcesses,
    required this.onRunWinetricksGui,
    required this.onRunInstaller,
    required this.onExploreHostFiles,
    required this.onRunWinecfg,
    required this.onRenamePrefix, // Add rename callback
    required this.onApplyControllerFix, // Add controller fix callback
    required this.onEditEnvVariables, // Add environment variables callback
  }) : super(key: key);

  @override
  State<ManagePrefixesPage> createState() => _ManagePrefixesPageState();
}

class _ManagePrefixesPageState extends State<ManagePrefixesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Prefixes'),
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wine Section Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: Row(
                children: [
                  const Icon(Icons.wine_bar),
                  const SizedBox(width: 8),
                  Text(
                    'Wine Prefixes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            // Wine Prefixes
            SizedBox(
              height: 300, // Fixed height for the wine section
              child: PrefixManagementPage(
                settings: widget.settings,
                onAddExecutable: widget.onAddExecutable,
                onShowCommonComponents: widget.onShowCommonComponents,
                onDeletePrefix: widget.onDeletePrefix,
                onDeleteExecutable: widget.onDeleteExecutable,
                onRenamePrefix: widget.onRenamePrefix,
                onRunExe: widget.onRunExe,
                onKillProcess: widget.onKillProcess,
                runningProcesses: widget.runningProcesses,
                onRunWinetricksGui: widget.onRunWinetricksGui,
                onRunInstaller: widget.onRunInstaller,
                onExploreHostFiles: widget.onExploreHostFiles,
                onRunWinecfg: widget.onRunWinecfg,
                onApplyControllerFix: widget.onApplyControllerFix,
                onEditEnvVariables: widget.onEditEnvVariables,
                prefixTypeFilter: PrefixType.wine,
              ),
            ),
            
            // Proton Section Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: Row(
                children: [
                  const Icon(Icons.games),
                  const SizedBox(width: 8),
                  Text(
                    'Proton Prefixes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            // Proton Prefixes
            SizedBox(
              height: 300, // Fixed height for the proton section
              child: PrefixManagementPage(
                settings: widget.settings,
                onAddExecutable: widget.onAddExecutable,
                onShowCommonComponents: widget.onShowCommonComponents,
                onDeletePrefix: widget.onDeletePrefix,
                onDeleteExecutable: widget.onDeleteExecutable,
                onRenamePrefix: widget.onRenamePrefix,
                onRunExe: widget.onRunExe,
                onKillProcess: widget.onKillProcess,
                runningProcesses: widget.runningProcesses,
                onRunWinetricksGui: widget.onRunWinetricksGui,
                onRunInstaller: widget.onRunInstaller,
                onExploreHostFiles: widget.onExploreHostFiles,
                onRunWinecfg: widget.onRunWinecfg,
                onApplyControllerFix: widget.onApplyControllerFix,
                onEditEnvVariables: widget.onEditEnvVariables,
                prefixTypeFilter: PrefixType.proton,
              ),
            ),
          ],
        ),
      ),
    );
  }
}