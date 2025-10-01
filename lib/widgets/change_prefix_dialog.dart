import 'package:flutter/material.dart';
import '../models/prefix_models.dart';

class ChangePrefixDialog extends StatefulWidget {
  final GameEntry gameEntry;
  final List<WinePrefix> allPrefixes;
  final Function(WinePrefix) onPrefixSelected; // Callback when confirmed

  const ChangePrefixDialog({
    super.key,
    required this.gameEntry,
    required this.allPrefixes,
    required this.onPrefixSelected,
  });

  @override
  State<ChangePrefixDialog> createState() => _ChangePrefixDialogState();
}

class _ChangePrefixDialogState extends State<ChangePrefixDialog> {
  WinePrefix? _selectedDestinationPrefix;
  late List<WinePrefix> _availableDestinations;

  @override
  void initState() {
    super.initState();
    // Filter out the current prefix
    _availableDestinations = widget.allPrefixes
        .where((p) => p.path != widget.gameEntry.prefix.path)
        .toList();
    // Sort for consistent order
    _availableDestinations.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    // Pre-select the first available destination if any
    if (_availableDestinations.isNotEmpty) {
      _selectedDestinationPrefix = _availableDestinations.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Change Prefix for "${widget.gameEntry.exe.name}"'),
      content: SizedBox(
        width: 400, // Give the dialog some width
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Prefix: ${widget.gameEntry.prefix.name}'),
            const SizedBox(height: 20),
            if (_availableDestinations.isEmpty)
              const Text('No other prefixes available to move to.')
            else ...[
              const Text('Select New Prefix:'),
              const SizedBox(height: 8),
              // Use DropdownButton for selection
              DropdownButton<WinePrefix>(
                value: _selectedDestinationPrefix,
                isExpanded: true,
                hint: const Text('Select a prefix'),
                items: _availableDestinations.map((prefix) {
                  return DropdownMenuItem<WinePrefix>(
                    value: prefix,
                    child: Text(prefix.name),
                  );
                }).toList(),
                onChanged: (WinePrefix? newValue) {
                  setState(() {
                    _selectedDestinationPrefix = newValue;
                  });
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_selectedDestinationPrefix == null)
              ? null // Disable if no destination is selected or available
              : () {
                  widget.onPrefixSelected(_selectedDestinationPrefix!);
                  Navigator.of(context).pop(); // Close this dialog
                },
          child: const Text('Confirm Change'),
        ),
      ],
    );
  }
}