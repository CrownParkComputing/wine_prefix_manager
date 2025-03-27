import 'dart:io'; // Needed for Process.run
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // Needed for file selection
import 'package:path/path.dart' as p; // For path manipulation
import '../models/prefix_models.dart'; // Import the prefix models

// Define callback types for actions
typedef OnPrefixAction = Future<void> Function(WinePrefix prefix);
typedef OnExeAction = Future<void> Function(WinePrefix prefix, ExeEntry exe);
typedef OnStringAction = Future<void> Function(String path); // For simple path actions

class PrefixManagementPage extends StatefulWidget {
  final List<WinePrefix> prefixes;
  final OnPrefixAction onAddExecutable;
  final OnPrefixAction onDeletePrefix;
  final OnExeAction onRunExe;
  final OnExeAction onKillProcess; // Add callback for killing process
  final Map<String, int> runningProcesses; // Pass the map of running processes

  const PrefixManagementPage({
    Key? key,
    required this.prefixes,
    required this.onAddExecutable,
    required this.onDeletePrefix,
    required this.onRunExe,
    required this.onKillProcess,
    required this.runningProcesses,
  }) : super(key: key);

  @override
  State<PrefixManagementPage> createState() => _PrefixManagementPageState();
}

class _PrefixManagementPageState extends State<PrefixManagementPage> {

  // No longer need the placeholder list
  // final List<String> _prefixes = [ ... ];

  Future<void> _runInstaller(String prefixPath) async {
    // Show loading indicator or disable button while processing
    if (!mounted) return; // Check if widget is still in the tree
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing installer...')),
    );

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe', 'msi', 'bat'],
      );

      if (result != null && result.files.single.path != null) {
        String installerPath = result.files.single.path!;
        final command = 'wine'; // Assuming wine is in PATH
        final args = [installerPath];
        final environment = {'WINEPREFIX': prefixPath};

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Running installer: ${p.basename(installerPath)}...')),
        );

        // Consider using process_run for better process management if needed
        final processResult = await Process.run(
          command,
          args,
          environment: environment,
          runInShell: true, // Important for environment variables
        );

        if (!mounted) return;
        if (processResult.exitCode == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Installer finished successfully.')),
          );
        } else {
          print('Error running installer: ${processResult.stderr}');
          print('Stdout: ${processResult.stdout}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Installer failed (code ${processResult.exitCode}). Check console for details.'),
              duration: const Duration(seconds: 8),
            ),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Installer selection cancelled.')),
        );
      }
    } catch (e) {
      print('Error in _runInstaller: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      // Hide loading indicator or re-enable button if you added one
    }
  }

  // _addExecutable is now handled by the callback widget.onAddExecutable
  // _deletePrefix is now handled by the callback widget.onDeletePrefix

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prefix Management'),
        // You might want to add a refresh button or filter options here later
      ),
      body: widget.prefixes.isEmpty
          ? const Center(child: Text('No prefixes found. Create one first!'))
          : ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: widget.prefixes.length,
              itemBuilder: (context, index) {
                final prefix = widget.prefixes[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  clipBehavior: Clip.antiAlias, // Ensures ExpansionTile respects card shape
                  child: ExpansionTile(
                     leading: Icon( // Add icon based on prefix type
                      prefix.type == PrefixType.wine ? Icons.wine_bar : Icons.gamepad,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      prefix.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      prefix.path,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    children: [ // Display executables inside the ExpansionTile
                      if (prefix.exeEntries.isEmpty)
                        const ListTile(
                          dense: true,
                          title: Text('No executables added yet.', style: TextStyle(fontStyle: FontStyle.italic)),
                        )
                      else
                        ...prefix.exeEntries.map((exe) {
                           final bool isRunning = widget.runningProcesses.containsKey(exe.path);
                           return ListTile(
                            dense: true,
                            leading: Icon(
                              exe.isGame ? Icons.sports_esports : Icons.play_circle_outline,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            title: Text(exe.name),
                            subtitle: Text(
                              exe.path,
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                isRunning ? Icons.stop_circle_outlined : Icons.play_arrow_outlined,
                                color: isRunning ? Colors.red : Colors.green,
                              ),
                              tooltip: isRunning ? 'Stop Process' : 'Run Executable',
                              onPressed: () => isRunning
                                  ? widget.onKillProcess(prefix, exe)
                                  : widget.onRunExe(prefix, exe),
                            ),
                          );
                        }).toList(),
                      // Actions for the prefix itself
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
                        child: Wrap(
                          spacing: 8.0,
                          runSpacing: 4.0,
                          alignment: WrapAlignment.start,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Add Executable'),
                              onPressed: () => widget.onAddExecutable(prefix), // Use callback
                              style: ElevatedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.download_for_offline),
                              label: const Text('Run Installer'),
                              onPressed: () => _runInstaller(prefix.path), // Use prefix path
                              style: ElevatedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            ElevatedButton.icon(
                              icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                              label: Text('Delete Prefix', style: TextStyle(color: Colors.red.shade700)),
                              onPressed: () => widget.onDeletePrefix(prefix), // Use callback
                              style: ElevatedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: Colors.red.shade700,
                              ),
                            ),
                            // Add other buttons like Rename, Configure etc. if needed
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
