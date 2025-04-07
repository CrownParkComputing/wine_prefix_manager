import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../pages/prefix_management_page.dart'; // Import the refactored page
import '../widgets/prefix_creation_form.dart'; // Import the new form widget

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
  // final OnPrefixContextAction onShowWinetricksVerbs; // Removed
  final OnShowDialogAction onShowCommonComponents; // Updated signature
  final OnPrefixAction onRunInstaller;
  final OnPrefixAction onExploreHostFiles;
  final Function(BuildContext, WinePrefix) onDeletePrefix; // Keep delete actions for now
  final Function(BuildContext, WinePrefix, ExeEntry) onDeleteExecutable; // Keep delete actions for now
  final OnPrefixContextAction onRunWinecfg; // Re-add
  final OnRenamePrefixAction onRenamePrefix; // Add rename callback

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
    // required this.onShowWinetricksVerbs, // Removed
    required this.onRunInstaller,
    required this.onExploreHostFiles,
    required this.onRunWinecfg,
    required this.onRenamePrefix, // Add rename callback
  }) : super(key: key);

  @override
  State<ManagePrefixesPage> createState() => _ManagePrefixesPageState();
}

class _ManagePrefixesPageState extends State<ManagePrefixesPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'Manage Prefixes'),
            Tab(icon: Icon(Icons.add_circle_outline), text: 'Create New Prefix'),
          ],
        ),
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // "Manage" Tab
          PrefixManagementPage(
            // Pass down all necessary callbacks
            settings: widget.settings,
            onAddExecutable: widget.onAddExecutable,
            onShowCommonComponents: widget.onShowCommonComponents, // Pass updated signature
            onDeletePrefix: widget.onDeletePrefix,
            onDeleteExecutable: widget.onDeleteExecutable,
            onRenamePrefix: widget.onRenamePrefix, // Pass rename callback
            // Pass down re-added callbacks
            onRunExe: widget.onRunExe,
            onKillProcess: widget.onKillProcess,
            runningProcesses: widget.runningProcesses,
            onRunWinetricksGui: widget.onRunWinetricksGui,
            // onShowWinetricksVerbs: widget.onShowWinetricksVerbs, // Removed
            onRunInstaller: widget.onRunInstaller,
            onExploreHostFiles: widget.onExploreHostFiles,
            onRunWinecfg: widget.onRunWinecfg,
          ),
          // "Create" Tab
          PrefixCreationForm(
            settings: widget.settings,
          ),
        ],
      ),
    );
  }
}