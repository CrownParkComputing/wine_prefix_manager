import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../services/wine_component_installer.dart';

// --- Reusable Confirmation Dialog ---
Future<bool?> showConfirmationDialog({
  required BuildContext context,
  required String title,
  required Widget content, // Use Widget for more flexible content
  required String confirmButtonText,
  required VoidCallback onConfirm,
}) async {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false, // User must tap button!
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: content,
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.of(dialogContext).pop(false); // Return false on cancel
            },
          ),
          FilledButton( // Use FilledButton for primary action
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error, // Use error color for delete confirmation
            ),
            child: Text(confirmButtonText),
            onPressed: () {
              onConfirm(); // Execute the callback
              Navigator.of(dialogContext).pop(true); // Return true on confirm
            },
          ),
        ],
      );
    },
  );
}
// --- End Reusable Confirmation Dialog ---


class CommonComponentsDialog extends StatefulWidget {
  final WinePrefix prefix;
  final Settings settings;

  const CommonComponentsDialog({
    Key? key,
    required this.prefix,
    required this.settings,
  }) : super(key: key);

  @override
  State<CommonComponentsDialog> createState() => _CommonComponentsDialogState();
}

class _CommonComponentsDialogState extends State<CommonComponentsDialog> {
  final WineComponentInstaller _installer = WineComponentInstaller();
  String _statusMessage = 'Select a component to install.';
  bool _isInstalling = false;

  void _updateStatus(String message) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
    }
  }

  Future<void> _installComponent(Future<bool> Function(WinePrefix, Settings, {Function(String)? progressCallback}) installFunction) async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _statusMessage = 'Starting installation...';
    });

    try {
      final success = await installFunction(
        widget.prefix,
        widget.settings,
        progressCallback: _updateStatus,
      );

      if (mounted) {
        setState(() {
          _statusMessage = success ? 'Installation successful!' : 'Installation failed. Check logs.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_statusMessage),
            backgroundColor: success ? Colors.green : Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error during installation: $e';
        });
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInstalling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isProtonPrefix = widget.prefix.type == PrefixType.proton;
    final String protonTooltip = 'Not applicable for Proton prefixes';

    return AlertDialog(
      title: Text('Install Common Components for "${widget.prefix.name}"'),
      content: SizedBox(
        width: 400, // Give the dialog some width
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Install necessary components like DXVK or VKD3D-Proton into the selected Wine prefix.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            if (isProtonPrefix)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  'Note: Manual installation is usually not needed for Proton prefixes as Proton manages these components.',
                  style: TextStyle(color: Theme.of(context).colorScheme.secondary),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Tooltip( // Wrap ElevatedButton.icon with Tooltip
                  message: isProtonPrefix ? protonTooltip : 'Install latest DXVK',
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Install DXVK'),
                    onPressed: _isInstalling || isProtonPrefix
                        ? null // Disable if installing or if it's a Proton prefix
                        : () => _installComponent(_installer.installDxvk),
                  ),
                ),
                Tooltip( // Wrap ElevatedButton.icon with Tooltip
                  message: isProtonPrefix ? protonTooltip : 'Install latest VKD3D-Proton',
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Install VKD3D'),
                    onPressed: _isInstalling || isProtonPrefix
                        ? null // Disable if installing or if it's a Proton prefix
                        : () => _installComponent(_installer.installVkd3d),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            // Progress/Status Area
            Row(
              children: [
                if (_isInstalling)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_isInstalling) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isInstalling ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}