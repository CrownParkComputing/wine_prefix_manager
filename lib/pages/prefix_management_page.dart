import 'dart:io'; // Needed for Process.run
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart'; // Needed for file selection
import 'package:path/path.dart' as p; // For path manipulation
import 'package:provider/provider.dart'; // Import Provider
import '../models/prefix_models.dart'; // Import the prefix models
import '../models/settings.dart'; // Import Settings model

import '../providers/prefix_provider.dart'; // Import the PrefixProvider
import '../services/wine_component_installer.dart'; // Import the WineComponentInstaller
import 'package:window_manager/window_manager.dart'; // Add this package
import '../providers/window_control_provider.dart'; // Add this import
import '../widgets/common_components_dialog.dart'; // Import the new dialog

// Define callback types for actions NOT handled by PrefixProvider
typedef OnExeAction = Future<void> Function(WinePrefix prefix, ExeEntry exe);
typedef OnPrefixAction = Future<void> Function(WinePrefix prefix); // Re-add for Add Executable
// typedef OnStringAction = Future<void> Function(String path); // No longer needed

class PrefixManagementPage extends StatefulWidget {
  final Settings? settings; // Add settings parameter
  // Remove parameters handled by PrefixProvider, except onAddExecutable
  // final List<WinePrefix> prefixes;
  final OnPrefixAction onAddExecutable; // Re-add this callback
  // final OnPrefixAction onDeletePrefix;
  final OnExeAction onRunExe; // Keep process-related callbacks
  final OnExeAction onKillProcess;
  // final OnExeAction onDeleteExe;
  // final OnPrefixAction onRunWinetricks;
  final Map<String, int> runningProcesses; // Keep running processes map

  const PrefixManagementPage({
    Key? key,
    required this.settings, // Make settings required
    // required this.prefixes,
    required this.onAddExecutable, // Re-add this required parameter
    // required this.onDeletePrefix,
    required this.onRunExe,
    required this.onKillProcess,
    // required this.onDeleteExe,
    // required this.onRunWinetricks,
    required this.runningProcesses,
  }) : super(key: key);

  @override
  State<PrefixManagementPage> createState() => _PrefixManagementPageState();
}

class _PrefixManagementPageState extends State<PrefixManagementPage> {

  // Local status for this page's specific actions (like installer)
  String _localStatus = '';

  // Add the component installer service
  final WineComponentInstaller _componentInstaller = WineComponentInstaller();
  bool _isInstallingComponent = false;
  Map<String, String> _installationStatusMap = {}; // Track status per prefix

  // Add the window control provider
  final WindowControlProvider _windowControlProvider = WindowControlProvider();

  Future<void> _runInstaller(String prefixPath) async {
    if (!mounted) return;
    setState(() { _localStatus = 'Selecting installer...'; }); // Use local status

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
         setState(() { _localStatus = 'Running installer: ${p.basename(installerPath)}...'; });

        // Consider using process_run for better process management if needed
        final processResult = await Process.run(
          command,
          args,
          environment: environment,
          runInShell: true, // Important for environment variables
        );

        if (!mounted) return;
        if (processResult.exitCode == 0) {
           setState(() { _localStatus = 'Installer finished successfully.'; });
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Installer finished successfully.')),
           );
        } else {
          print('Error running installer: ${processResult.stderr}');
          print('Stdout: ${processResult.stdout}');
           setState(() { _localStatus = 'Installer failed (code ${processResult.exitCode}). Check console.'; });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Installer failed (code ${processResult.exitCode}). Check console for details.'),
              duration: const Duration(seconds: 8),
            ),
          );
        }
      } else {
        if (!mounted) return;
         setState(() { _localStatus = 'Installer selection cancelled.'; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Installer selection cancelled.')),
        );
      }
    } catch (e) {
      print('Error in _runInstaller: $e');
      if (!mounted) return;
       setState(() { _localStatus = 'Error running installer: $e'; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // Add the installation method for DXVK and VKD3D
  Future<void> _installComponent(WinePrefix prefix, bool isDxvk) async {
    if (prefix.type != PrefixType.wine) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Component installation only supported for Wine prefixes')),
      );
      return;
    }
    
    setState(() {
      _isInstallingComponent = true;
      _installationStatusMap[prefix.path] = 'Starting installation...';
    });
    
    try {
      // Use widget.settings instead of provider
      if (widget.settings == null) {
        // Use setState for local status, not progressCallback
        setState(() => _installationStatusMap[prefix.path] = 'Error: Settings not loaded.');
        return; // Or throw an exception
      }
      final success = isDxvk
          ? await _componentInstaller.installDxvk(
              prefix,
              widget.settings!, // Pass settings from widget
              progressCallback: (message) {
                setState(() {
                  _installationStatusMap[prefix.path] = message;
                });
              },
            )
          : await _componentInstaller.installVkd3d(
              prefix,
              widget.settings!, // Pass settings from widget
              progressCallback: (message) {
                setState(() {
                  _installationStatusMap[prefix.path] = message;
                });
              },
            );
      
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to install ${isDxvk ? 'DXVK' : 'VKD3D-Proton'}'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${isDxvk ? 'DXVK' : 'VKD3D-Proton'} installed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _installationStatusMap[prefix.path] = 'Error: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isInstallingComponent = false;
      });
    }
 }

/// Opens the specified prefix directory in the system's default file manager.
Future<void> _explorePrefixFiles(WinePrefix prefix) async {
  final directoryPath = prefix.path;
  String command;
  List<String> args = [directoryPath];

  if (Platform.isLinux) {
    // Check for common file managers or use xdg-open
    final checkResult = await Process.run('which', ['xdg-open']);
    if (checkResult.exitCode == 0) {
      command = 'xdg-open';
    } else {
       // Basic fallback - might not work everywhere
       print("Warning: xdg-open not found. Attempting direct launch (might fail).");
       command = 'nautilus'; // Or dolphin, thunar etc. - less reliable
       // Consider adding checks for specific file managers if needed
    }
  } else if (Platform.isWindows) {
    command = 'explorer';
    // Windows explorer typically doesn't need the path as a separate argument like this
    // It might be better to run 'explorer "$directoryPath"' directly in shell
    args = [directoryPath]; // Keep for consistency, might need adjustment
  } else if (Platform.isMacOS) {
    command = 'open';
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unsupported operating system for exploring files.')),
    );
    return;
  }

  try {
    print('Attempting to open file explorer: $command ${args.join(' ')}');
    // Use runInShell: true for Windows explorer potentially
    await Process.run(command, args, runInShell: Platform.isWindows);
    // No reliable way to check success here, Process.run waits for exit.
    // If it fails, an exception might be caught below.
  } catch (e) {
    print('Error opening file explorer: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening file explorer: $e')),
      );
    }
  }
}


/// Runs winecfg for the specified prefix in a new terminal window.
Future<void> _runWinecfg(BuildContext context, WinePrefix prefix) async {
  // Reusing the terminal launching logic from _runWinetricks
  if (!Platform.isLinux) { // winecfg is primarily a Linux/Wine concept here
     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('winecfg is typically run on Linux with Wine.')));
     return;
  }

   // Check if terminal emulator exists
  final termCheckResult = await Process.run('which', ['gnome-terminal']);
  String terminalCommand = 'gnome-terminal';
  if (termCheckResult.exitCode != 0) {
      final konsoleCheck = await Process.run('which', ['konsole']);
      if (konsoleCheck.exitCode == 0) terminalCommand = 'konsole';
      else {
          final xtermCheck = await Process.run('which', ['xterm']);
          if (xtermCheck.exitCode == 0) terminalCommand = 'xterm';
          else {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No supported terminal emulator found (gnome-terminal, konsole, xterm).')));
             return;
          }
      }
  }

  if (mounted) {
     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Launching winecfg for "${prefix.name}"...')));
  }

  final command = terminalCommand;
  final args = [
      if (terminalCommand == 'konsole' || terminalCommand == 'xterm') '-e',
      if (terminalCommand == 'gnome-terminal') '--',
      'sh',
      '-c',
      // Set WINEPREFIX and run winecfg, keep terminal open
      'WINEPREFIX="${prefix.path}" wine winecfg; echo "winecfg closed. Press Enter to exit terminal."; read'
  ];

  try {
    await Process.start(command, args, runInShell: false);
    print('Launched terminal process for winecfg.');
     if (mounted) {
       // Optional: Update status or show persistent message
     }
  } catch (e) {
    print('Error launching winecfg: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error launching winecfg: $e')));
    }
  }
}

/// Shows a dialog to select and install common Winetricks components.
Future<void> _showInstallCommonComponentsDialog(BuildContext context, WinePrefix prefix) async {
  // Use the new CommonComponentsDialog
  final List<String>? selectedVerbs = await showDialog<List<String>>(
    context: context,
    builder: (context) => const CommonComponentsDialog(), // Show the actual dialog
  );

  // Check if the user selected any verbs and didn't cancel
  if (selectedVerbs != null && selectedVerbs.isNotEmpty) {
    await _runWinetricksInstall(context, prefix, selectedVerbs);
  } else if (selectedVerbs == null) {
    // User cancelled
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Component installation cancelled.')),
       );
    }
  } else {
     // User pressed install but selected nothing (dialog should prevent this, but handle anyway)
     if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('No components selected.')),
       );
     }
  }
}

/// Runs winetricks install for the specified verbs in a new terminal window.
Future<void> _runWinetricksInstall(BuildContext context, WinePrefix prefix, List<String> verbs) async {
  if (verbs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No components selected for installation.')));
    return;
  }
  if (!Platform.isLinux) {
     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Winetricks installation is typically run on Linux.')));
     return;
  }

   // Check if winetricks command exists
  final wtCheckResult = await Process.run('which', ['winetricks']);
  if (wtCheckResult.exitCode != 0) {
     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: "winetricks" command not found. Please install Winetricks.')));
     return;
  }

   // Check if terminal emulator exists
  final termCheckResult = await Process.run('which', ['gnome-terminal']);
  String terminalCommand = 'gnome-terminal';
  if (termCheckResult.exitCode != 0) {
      final konsoleCheck = await Process.run('which', ['konsole']);
      if (konsoleCheck.exitCode == 0) terminalCommand = 'konsole';
      else {
          final xtermCheck = await Process.run('which', ['xterm']);
          if (xtermCheck.exitCode == 0) terminalCommand = 'xterm';
          else {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No supported terminal emulator found (gnome-terminal, konsole, xterm).')));
             return;
          }
      }
  }

  final verbsString = verbs.join(' '); // Join selected verbs with spaces
  if (mounted) {
     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Launching Winetricks install for: $verbsString...')));
  }

  final command = terminalCommand;
  final args = [
      if (terminalCommand == 'konsole' || terminalCommand == 'xterm') '-e',
      if (terminalCommand == 'gnome-terminal') '--',
      'sh',
      '-c',
      // Set WINEPREFIX, run winetricks with verbs, keep terminal open
      'WINEPREFIX="${prefix.path}" winetricks $verbsString; echo "Winetricks install finished. Press Enter to exit terminal."; read'
  ];

  try {
    await Process.start(command, args, runInShell: false);
    print('Launched terminal process for Winetricks install.');
     if (mounted) {
       // Optional: Update status or show persistent message
     }
  } catch (e) {
    print('Error launching Winetricks install: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error launching Winetricks install: $e')));
    }
  }
}


 // --- Methods using Provider ---

 // Future<void> _addExecutable(...) async { ... } // Removed, logic is handled by the callback passed to the widget

  Future<void> _deleteExecutable(BuildContext context, WinePrefix prefix, ExeEntry exeToDelete) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text('Are you sure you want to delete the executable "${exeToDelete.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Use context.read to access provider without listening
      final prefixProvider = context.read<PrefixProvider>();
      await prefixProvider.deleteExecutable(prefix, exeToDelete);
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(prefixProvider.status)), // Show status from provider
         );
      }
    }
  }

   Future<void> _deletePrefix(BuildContext context, WinePrefix prefixToDelete) async {
     final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete Prefix'),
        content: Text('Are you sure you want to delete the prefix "${prefixToDelete.name}" and all its contents? This action CANNOT be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('DELETE', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

     if (confirmed == true) {
        final prefixProvider = context.read<PrefixProvider>();
        // TODO: Add actual directory deletion logic in the provider or service
        await prefixProvider.deletePrefix(prefixToDelete);
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text(prefixProvider.status)), // Show provider status
           );
        }
     }
   }

   Future<void> _runWinetricks(BuildContext context, WinePrefix prefix) async {
      // This logic involves platform checks and Process.start, keep it local for now.
      // Could be moved to a service if it becomes more complex.
      if (!Platform.isLinux) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Winetricks can only be run on Linux.')));
         return;
      }

      // Check if winetricks command exists
      final checkResult = await Process.run('which', ['winetricks']);
      if (checkResult.exitCode != 0) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: "winetricks" command not found. Please install Winetricks.')));
         return;
      }
       // Check if terminal emulator exists
      final termCheckResult = await Process.run('which', ['gnome-terminal']);
      String terminalCommand = 'gnome-terminal';
      if (termCheckResult.exitCode != 0) {
          final konsoleCheck = await Process.run('which', ['konsole']);
          if (konsoleCheck.exitCode == 0) terminalCommand = 'konsole';
          else {
              final xtermCheck = await Process.run('which', ['xterm']);
              if (xtermCheck.exitCode == 0) terminalCommand = 'xterm';
              else {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: No supported terminal emulator found (gnome-terminal, konsole, xterm).')));
                 return;
              }
          }
      }

      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Launching Winetricks for "${prefix.name}"...')));
      }

      final command = terminalCommand;
      final args = [
          if (terminalCommand == 'konsole' || terminalCommand == 'xterm') '-e',
          if (terminalCommand == 'gnome-terminal') '--',
          'sh',
          '-c',
          'WINEPREFIX="${prefix.path}" winetricks; echo "Winetricks closed. Press Enter to exit terminal."; read'
      ];

      try {
        await Process.start(command, args, runInShell: false);
        print('Launched terminal process for Winetricks.');
         if (mounted) {
           // Maybe update local status or show a persistent message?
         }
      } catch (e) {
        print('Error launching Winetricks: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error launching Winetricks: $e')));
        }
      }
   }


  @override
  Widget build(BuildContext context) {
    return Consumer<PrefixProvider>(
      builder: (context, prefixProvider, child) {
        final prefixes = prefixProvider.prefixes;

        return Scaffold(
          // appBar: AppBar(...), // REMOVED AppBar from this page
          body: Column( // Body is now the direct child of Scaffold
            children: [
              // Loading Indicator from Provider
              if (prefixProvider.isLoading)
                 const Padding(
                   padding: EdgeInsets.all(8.0),
                   child: Center(child: LinearProgressIndicator()),
                 ),
              // Status Message from Provider (optional display area)
              if (prefixProvider.status.isNotEmpty && !prefixProvider.isLoading)
                 Padding(
                   padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                   child: Text('Status: ${prefixProvider.status}', style: Theme.of(context).textTheme.bodySmall),
                 ),
              // Local Status Message
              if (_localStatus.isNotEmpty)
                 Padding(
                   padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                   child: Text('Action: $_localStatus', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                 ),
              // Add Refresh Button here
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh Prefixes',
                    onPressed: () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('Scanning for prefixes...')),
                      );
                      await prefixProvider.scanForPrefixes(); // Trigger scan
                      if (mounted) { // Show result after scan
                         ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(content: Text(prefixProvider.status)),
                         );
                      }
                    },
                  ),
                ),
              ),
              // Prefix List
              Expanded( // Make ListView take remaining space
                child: prefixes.isEmpty
                    ? const Center(child: Text('No prefixes found. Create one or Refresh!'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: prefixes.length,
                        itemBuilder: (context, index) {
                          final prefix = prefixes[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                            clipBehavior: Clip.antiAlias,
                            child: ExpansionTile(
                              leading: Icon(
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
                              children: [
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
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton( // Run/Kill - Use WIDGET callbacks
                                            icon: Icon(
                                              isRunning ? Icons.stop_circle_outlined : Icons.play_arrow_outlined,
                                              color: isRunning ? Colors.red : Colors.green,
                                            ),
                                            tooltip: isRunning ? 'Stop Process' : 'Run Executable',
                                            onPressed: () => isRunning
                                                ? widget.onKillProcess(prefix, exe)
                                                : widget.onRunExe(prefix, exe),
                                          ),
                                          IconButton( // Delete executable - Use LOCAL method calling PROVIDER
                                            icon: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
                                            tooltip: 'Delete Executable',
                                            onPressed: () => _deleteExecutable(context, prefix, exe),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),

                                // Add component installation UI
                                if (prefix.type == PrefixType.wine) 
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Divider(),
                                        const Text(
                                          'Graphics Components',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.download),
                                              label: const Text('Install DXVK'),
                                              onPressed: _isInstallingComponent 
                                                  ? null 
                                                  : () => _installComponent(prefix, true),
                                              style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
                                            ),
                                            const SizedBox(width: 8),
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.download),
                                              label: const Text('Install VKD3D-Proton'),
                                              onPressed: _isInstallingComponent 
                                                  ? null 
                                                  : () => _installComponent(prefix, false),
                                              style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
                                            ),
                                          ],
                                        ),
                                        if (_installationStatusMap.containsKey(prefix.path) && 
                                            _installationStatusMap[prefix.path]!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                                            child: _isInstallingComponent
                                                ? Row(
                                                    children: [
                                                      const SizedBox(
                                                        height: 16,
                                                        width: 16,
                                                        child: CircularProgressIndicator(strokeWidth: 2),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          _installationStatusMap[prefix.path] ?? '',
                                                          style: Theme.of(context).textTheme.bodySmall,
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : Text(
                                                    _installationStatusMap[prefix.path] ?? '',
                                                    style: Theme.of(context).textTheme.bodySmall,
                                                  ),
                                          ),
                                      ],
                                    ),
                                  ),
                                const Divider(), // Add a divider for visual separation
                               Padding(
                                  padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
                                  child: Wrap(
                                    spacing: 8.0,
                                    runSpacing: 8.0, // Increased vertical spacing
                                    alignment: WrapAlignment.start,
                                    children: [
                                      Tooltip(
                                        message: 'Add Executable',
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.add),
                                          label: const SizedBox.shrink(), // Remove label visually
                                          // Call the widget's callback, which triggers the logic in HomePage
                                          onPressed: () => widget.onAddExecutable(prefix),
                                          style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)), // Adjust padding for icon only
                                        ),
                                      ),
                                      Tooltip(
                                        message: 'Run Installer',
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.download_for_offline),
                                          label: const SizedBox.shrink(), // Remove label visually
                                          onPressed: () => _runInstaller(prefix.path), // Use local method
                                          style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)), // Adjust padding
                                        ),
                                      ),
                                      Tooltip(
                                        message: 'Run Winetricks',
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.settings_applications_outlined),
                                          label: const SizedBox.shrink(), // Remove label visually
                                          onPressed: () => _runWinetricks(context, prefix), // Use local method
                                          style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)), // Adjust padding
                                        ),
                                      ),
                                      Tooltip(
                                        message: 'Explore Files',
                                        child: ElevatedButton.icon( // Added Explore Files button
                                          icon: const Icon(Icons.folder_open_outlined),
                                          label: const SizedBox.shrink(), // Remove label visually
                                          onPressed: () => _explorePrefixFiles(prefix),
                                          style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)), // Adjust padding
                                        ),
                                      ),
                                      Tooltip(
                                        message: 'Run winecfg',
                                        child: ElevatedButton.icon( // Added Run winecfg button
                                          icon: const Icon(Icons.settings_input_component_outlined),
                                          label: const SizedBox.shrink(), // Remove label visually
                                          onPressed: () => _runWinecfg(context, prefix),
                                          style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)), // Adjust padding
                                        ),
                                      ),
                                      Tooltip(
                                        message: 'Install Common Components',
                                        child: ElevatedButton.icon( // Added Install Common Components button
                                          icon: const Icon(Icons.build_circle_outlined),
                                          label: const SizedBox.shrink(), // Remove label visually
                                          onPressed: () => _showInstallCommonComponentsDialog(context, prefix),
                                          style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)), // Adjust padding
                                        ),
                                      ),
                                      Tooltip(
                                        message: 'Delete Prefix',
                                        child: ElevatedButton.icon(
                                          icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                                          label: const SizedBox.shrink(), // Remove label visually
                                          onPressed: () => _deletePrefix(context, prefix), // Use local method calling PROVIDER
                                          style: ElevatedButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            foregroundColor: Theme.of(context).colorScheme.error,
                                            padding: const EdgeInsets.symmetric(horizontal: 12), // Adjust padding
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  ),
                                ],
                              ), // Closes ExpansionTile
                            ); // Closes Card
                          }, // Closes itemBuilder
                        ), // Closes ListView.builder
                      ), // Closes Expanded
              ], // Closes Column children
            ), // Closes Column
        ); // Closes Scaffold
      }, // Closes Consumer builder
    ); // Closes Consumer
  }
}
