import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../providers/prefix_provider.dart';
import '../widgets/rename_prefix_dialog.dart';
import '../widgets/env_variables_dialog.dart';
import '../widgets/prefix_list_tile.dart';
import '../widgets/prefix_detail_actions.dart';
import '../widgets/executable_list_tile.dart';

// Define callback types needed by child widgets, to be passed from main.dart
typedef OnExeAction = Future<void> Function(WinePrefix prefix, ExeEntry exe);
typedef PrefixActionCallback = Future<void> Function(WinePrefix prefix);
typedef PrefixContextActionCallback = Future<void> Function(BuildContext context, WinePrefix prefix);
typedef OnRenamePrefixAction = Future<void> Function(BuildContext context, WinePrefix prefix, String newName);

class ManagePrefixesPage extends StatefulWidget {
  final Settings settings;
  final Function(WinePrefix prefix) onAddExecutable;
  final OnExeAction onRunExe;
  final OnExeAction onKillProcess;
  final Map<String, int> runningProcesses;
  final PrefixActionCallback onRunWinetricksGui;
  final PrefixContextActionCallback onShowCommonComponents;
  final PrefixActionCallback onRunInstaller;
  final PrefixActionCallback onExploreHostFiles;
  final Function(BuildContext, WinePrefix) onDeletePrefix;
  final Function(BuildContext, WinePrefix, ExeEntry) onDeleteExecutable;
  final PrefixContextActionCallback onRunWinecfg;
  final OnRenamePrefixAction onRenamePrefix;
  final PrefixContextActionCallback onApplyControllerFix;
  final PrefixContextActionCallback onEditEnvVariables;

  const ManagePrefixesPage({
    Key? key,
    required this.settings,
    required this.onAddExecutable,
    required this.onShowCommonComponents,
    required this.onDeletePrefix,
    required this.onDeleteExecutable,
    required this.onRunExe,
    required this.onKillProcess,
    required this.runningProcesses,
    required this.onRunWinetricksGui,
    required this.onRunInstaller,
    required this.onExploreHostFiles,
    required this.onRunWinecfg,
    required this.onRenamePrefix,
    required this.onApplyControllerFix,
    required this.onEditEnvVariables,
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

  void _showRenameDialog(BuildContext context, WinePrefix prefix) {
    showDialog(
      context: context,
      builder: (dialogContext) => RenamePrefixDialog(
        prefixToRename: prefix,
        onConfirmRename: (newName) {
          widget.onRenamePrefix(context, prefix, newName);
        },
      ),
    );
  }

  void _showWineComponentSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wine Component Settings'),
        content: const SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Wine component settings can be configured per-prefix using the actions in each prefix card below.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              Text(
                'Available actions:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Run Winetricks GUI'),
              Text('• Install Common Components'),
              Text('• Run Wine Configuration'),
              Text('• Apply Controller Fixes'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Prefixes'),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_applications_outlined),
            tooltip: 'Wine Component Settings',
            onPressed: () => _showWineComponentSettings(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(
              icon: Icon(Icons.wine_bar),
              text: 'Wine Prefixes',
            ),
            Tab(
              icon: Icon(Icons.games),
              text: 'Proton Prefixes',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPrefixList(PrefixType.wine),
          _buildPrefixList(PrefixType.proton),
        ],
      ),
    );
  }

  Widget _buildPrefixList(PrefixType type) {
    return Consumer<PrefixProvider>(
      builder: (context, prefixProvider, child) {
        final prefixes = prefixProvider.prefixes
            .where((prefix) => prefix.type == type)
            .toList();

        if (prefixes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  type == PrefixType.wine ? Icons.wine_bar : Icons.games,
                  size: 64,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  'No ${type.name} prefixes found.',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create a new prefix using the "Prefix Management" tab.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: prefixes.length,
          itemBuilder: (context, index) {
            final prefix = prefixes[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        Text(
                          'Build: ${prefix.wineBuildPath}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  PrefixDetailActions(
                    prefix: prefix,
                    settings: widget.settings,
                    onAddExecutable: widget.onAddExecutable,
                    onShowCommonComponents: widget.onShowCommonComponents,
                    onDeletePrefix: widget.onDeletePrefix,
                    onRenamePrefix: (ctx, pfx) => _showRenameDialog(ctx, pfx),
                    onRunWinecfg: widget.onRunWinecfg,
                    onRunWinetricksGui: widget.onRunWinetricksGui,
                    onRunInstaller: widget.onRunInstaller,
                    onExploreHostFiles: widget.onExploreHostFiles,
                    onApplyControllerFix: widget.onApplyControllerFix,
                    onEditEnvVariables: widget.onEditEnvVariables,
                  ),
                  if (prefix.exeEntries.isNotEmpty) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16.0,
                        right: 16.0,
                        top: 16.0,
                        bottom: 8.0,
                      ),
                      child: Text(
                        'Executables:',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: prefix.exeEntries.length,
                      itemBuilder: (context, exeIndex) {
                        final exe = prefix.exeEntries[exeIndex];
                        final isRunning = widget.runningProcesses.containsKey(exe.path);
                        return ExecutableListTile(
                          prefix: prefix,
                          exe: exe,
                          isRunning: isRunning,
                          onRunExe: widget.onRunExe,
                          onKillProcess: widget.onKillProcess,
                          onDeleteExe: widget.onDeleteExecutable,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ] else
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 16.0,
                      ),
                      child: Text('No executables added to this prefix yet.'),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}