import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import 'package:provider/provider.dart';
import '../providers/prefix_provider.dart';

class EnvVariablesDialog extends StatefulWidget {
  final WinePrefix prefix;

  const EnvVariablesDialog({
    Key? key,
    required this.prefix,
  }) : super(key: key);

  @override
  State<EnvVariablesDialog> createState() => _EnvVariablesDialogState();
}

class _EnvVariablesDialogState extends State<EnvVariablesDialog> {
  late Map<String, String> _environmentVariables;
  final _envKeyController = TextEditingController();
  final _envValueController = TextEditingController();
  final _combinedInputController = TextEditingController(); // For KEY=VALUE format input
  final _formKey = GlobalKey<FormState>();
  final _combinedFormKey = GlobalKey<FormState>(); // Separate form key for combined input
  
  // Predefined environment variables for DirectX support
  final List<Map<String, dynamic>> _presetEnvVars = [
    {
      'name': 'DirectX 12 Compatibility',
      'description': 'Enables DirectX 12 to Vulkan translation with good performance',
      'vars': <String, String>{
        'WINEESYNC': '1',
        'WINEFSYNC': '1',
        'VKD3D_DEBUG': 'none',
      }
    },
    {
      'name': 'DXVK Debug Info',
      'description': 'Shows FPS and API info for DXVK (DX9-11)',
      'vars': <String, String>{
        'DXVK_HUD': 'api,fps',
      }
    },
    {
      'name': 'VKD3D Debug Info',
      'description': 'Enables debugging for VKD3D (DX12)',
      'vars': <String, String>{
        'VKD3D_DEBUG': 'warn',
      }
    },
    {
      'name': 'Performance Tuning',
      'description': 'Sets CPU thread priority for better gaming performance',
      'vars': <String, String>{
        'WINE_CPU_SCHEDULER': 'fifo',
        'WINE_CPU_PRIORITY': 'high',
      }
    },
    {
      'name': 'Advanced DXVK Configuration',
      'description': 'Detailed DXVK HUD with more information',
      'vars': <String, String>{
        'DXVK_HUD': 'api,fps,version,compiler',
        'DXVK_LOG_LEVEL': 'debug',
      }
    },
  ];

  @override
  void initState() {
    super.initState();
    // Create a copy of the environment variables to work with
    _environmentVariables = Map.from(widget.prefix.environmentVariables);
  }

  @override
  void dispose() {
    _envKeyController.dispose();
    _envValueController.dispose();
    _combinedInputController.dispose();
    super.dispose();
  }

  void _addVariable() {
    if (_formKey.currentState!.validate()) {
      final key = _envKeyController.text.trim();
      final value = _envValueController.text.trim();
      
      setState(() {
        _environmentVariables[key] = value;
        _envKeyController.clear();
        _envValueController.clear();
      });
    }
  }

  void _addCombinedVariable() {
    if (_combinedFormKey.currentState!.validate()) {
      final input = _combinedInputController.text.trim();
      final equalIndex = input.indexOf('=');
      
      if (equalIndex > 0 && equalIndex < input.length - 1) {
        final key = input.substring(0, equalIndex).trim();
        final value = input.substring(equalIndex + 1).trim();
        
        setState(() {
          _environmentVariables[key] = value;
          _combinedInputController.clear();
        });
      }
    }
  }

  void _removeVariable(String key) {
    setState(() {
      _environmentVariables.remove(key);
    });
  }

  void _applyPreset(Map<String, dynamic> preset) {
    if (preset.containsKey('vars') && preset['vars'] is Map<String, String>) {
      final Map<String, String> variables = preset['vars'] as Map<String, String>;
      setState(() {
        _environmentVariables.addAll(variables);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Environment Variables for "${widget.prefix.name}"',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Environment variables will be applied when running games in this prefix. '
                'These can improve compatibility with DirectX 12 games and performance.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),

              // Presets section
              ExpansionTile(
                title: const Text('Apply Presets'),
                subtitle: const Text('Quick configuration for common scenarios'),
                children: _presetEnvVars.map((preset) => 
                  ListTile(
                    title: Text(preset['name'] as String),
                    subtitle: Text(preset['description'] as String),
                    trailing: OutlinedButton(
                      child: const Text('Apply'),
                      onPressed: () => _applyPreset(preset),
                    ),
                  )
                ).toList(),
              ),
              
              const SizedBox(height: 12),
              // Add combined KEY=VALUE input
              Form(
                key: _combinedFormKey,
                child: Row(
                  children: [
                    Expanded(
                      flex: 7,
                      child: TextFormField(
                        controller: _combinedInputController,
                        decoration: const InputDecoration(
                          labelText: 'Paste KEY=VALUE Format',
                          hintText: 'e.g., DXVK_HUD=api,fps,version',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a variable in KEY=VALUE format';
                          }
                          if (!value.contains('=')) {
                            return 'Must contain "=" character';
                          }
                          final parts = value.split('=');
                          if (parts[0].trim().isEmpty) {
                            return 'Key name cannot be empty';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle),
                      onPressed: _addCombinedVariable,
                      tooltip: 'Add Combined Variable',
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              
              // Individual key-value input
              Form(
                key: _formKey,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _envKeyController,
                        decoration: const InputDecoration(
                          labelText: 'Variable Name',
                          hintText: 'e.g., DXVK_HUD',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a variable name';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: _envValueController,
                        decoration: const InputDecoration(
                          labelText: 'Value',
                          hintText: 'e.g., fps,api',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a value';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle),
                      onPressed: _addVariable,
                      tooltip: 'Add Variable',
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              Text(
                'Current Environment Variables (${_environmentVariables.length}):',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              
              Expanded(
                child: _environmentVariables.isEmpty
                    ? const Center(child: Text('No environment variables set'))
                    : Card(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _environmentVariables.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final key = _environmentVariables.keys.elementAt(index);
                            final value = _environmentVariables[key]!;
                            return ListTile(
                              dense: true,
                              title: Text(key, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(value),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, size: 20),
                                onPressed: () => _removeVariable(key),
                                tooltip: 'Remove',
                              ),
                            );
                          },
                        ),
                      ),
              ),
              
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final prefixProvider = Provider.of<PrefixProvider>(context, listen: false);
                      final updatedPrefix = widget.prefix.copyWith(
                        environmentVariables: _environmentVariables,
                      );
                      prefixProvider.updatePrefix(updatedPrefix);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
} 