import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/prefix_models.dart';
import '../providers/prefix_provider.dart'; // To check for existing names

class RenamePrefixDialog extends StatefulWidget {
  final WinePrefix prefixToRename;
  final Function(String newName) onConfirmRename;

  const RenamePrefixDialog({
    Key? key,
    required this.prefixToRename,
    required this.onConfirmRename,
  }) : super(key: key);

  @override
  State<RenamePrefixDialog> createState() => _RenamePrefixDialogState();
}

class _RenamePrefixDialogState extends State<RenamePrefixDialog> {
  late TextEditingController _nameController;
  final _formKey = GlobalKey<FormState>();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.prefixToRename.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Prefix name cannot be empty.';
    }
    if (value.trim() == widget.prefixToRename.name) {
      return 'New name must be different from the current name.';
    }
    // Check for invalid characters (e.g., slashes)
    if (value.contains('/') || value.contains('\\')) {
       return 'Prefix name cannot contain slashes.';
    }
    // Check if name already exists (using Provider)
    final prefixProvider = Provider.of<PrefixProvider>(context, listen: false);
    if (prefixProvider.prefixes.any((p) => p.name == value.trim())) {
      return 'Prefix name "$value" already exists.';
    }
    return null;
  }

  void _submitForm() {
    setState(() {
      _errorMessage = null; // Clear previous error
    });
    if (_formKey.currentState!.validate()) {
      final newName = _nameController.text.trim();
      try {
        widget.onConfirmRename(newName);
        Navigator.of(context).pop(); // Close dialog on success
      } catch (e) {
        // Handle potential errors from the rename logic (e.g., file system error)
        setState(() {
          _errorMessage = 'Error renaming prefix: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rename Prefix "${widget.prefixToRename.name}"'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'New Prefix Name',
                border: OutlineInputBorder(),
              ),
              validator: _validateName,
              onFieldSubmitted: (_) => _submitForm(), // Allow submitting with Enter key
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitForm,
          child: const Text('Rename'),
        ),
      ],
    );
  }
}