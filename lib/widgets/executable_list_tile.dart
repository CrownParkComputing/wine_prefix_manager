import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import 'common_components_dialog.dart'; // Import for confirmation dialog

// Define callback types required by this widget
typedef ExeActionCallback = void Function(WinePrefix prefix, ExeEntry exe);
typedef ExeContextActionCallback = void Function(BuildContext context, WinePrefix prefix, ExeEntry exe);

class ExecutableListTile extends StatelessWidget {
  final WinePrefix prefix;
  final ExeEntry exe;
  final bool isRunning;
  final ExeActionCallback onRunExe;
  final ExeActionCallback onKillProcess;
  final ExeContextActionCallback onDeleteExe; // Needs context for dialog

  const ExecutableListTile({
    Key? key,
    required this.prefix,
    required this.exe,
    required this.isRunning,
    required this.onRunExe,
    required this.onKillProcess,
    required this.onDeleteExe,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(exe.isGame ? Icons.sports_esports : Icons.apps),
      title: Text(exe.name),
      subtitle: Text(
        exe.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(isRunning ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            tooltip: isRunning ? 'Stop' : 'Run',
            color: isRunning ? Colors.red : Colors.green,
            onPressed: () => isRunning ? onKillProcess(prefix, exe) : onRunExe(prefix, exe),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete Executable',
            onPressed: () { // Modified onPressed for confirmation
              showConfirmationDialog(
                context: context,
                title: 'Delete Executable?',
                content: Text('Are you sure you want to remove the executable "${exe.name}" from the prefix "${prefix.name}"?\n\nThis only removes the entry from the manager, it does not delete the actual file.'),
                confirmButtonText: 'Delete',
                onConfirm: () => onDeleteExe(context, prefix, exe), // Call original callback on confirm
              );
            },
          ),
          // Consider adding an Edit button here later that calls _editGameDetails
          // IconButton(
          //   icon: const Icon(Icons.edit),
          //   tooltip: 'Edit Details',
          //   onPressed: () { /* Call edit details callback */ },
          // ),
        ],
      ),
      // Optional: Add onTap to edit details directly?
      // onTap: () { /* Call edit details callback */ },
    );
  }
}