import 'package:flutter/material.dart';

// Data structure for a Winetricks component
class WinetricksComponent {
  final String verb; // The actual winetricks verb
  final String name; // User-friendly name
  final String description; // Optional description

  const WinetricksComponent({
    required this.verb,
    required this.name,
    this.description = '',
  });
}

// List of common components to offer
const List<WinetricksComponent> commonComponents = [
  WinetricksComponent(verb: 'corefonts', name: 'Core Fonts', description: 'Common Microsoft Web Fonts'),
  WinetricksComponent(verb: 'vcrun2019', name: 'Visual C++ 2019 Runtimes', description: 'Includes 2015, 2017, 2019'),
  WinetricksComponent(verb: 'vcrun2022', name: 'Visual C++ 2022 Runtimes', description: 'Includes 2015, 2017, 2019, 2022'),
  WinetricksComponent(verb: 'dotnet48', name: '.NET Framework 4.8', description: 'Microsoft .NET Runtime 4.8'),
  // Common DirectX components (often needed even with DXVK/VKD3D)
  WinetricksComponent(verb: 'd3dx9', name: 'DirectX 9 Runtimes', description: 'Legacy DirectX 9 components'),
  WinetricksComponent(verb: 'd3dcompiler_43', name: 'Direct3D Compiler 43', description: 'Shader compiler library'),
  WinetricksComponent(verb: 'd3dcompiler_47', name: 'Direct3D Compiler 47', description: 'Newer shader compiler library'),
  // Note: DXVK/VKD3D are handled by separate buttons, but could be listed here if desired
  // WinetricksComponent(verb: 'dxvk', name: 'DXVK', description: 'Vulkan-based D3D9/10/11 implementation'),
];

class CommonComponentsDialog extends StatefulWidget {
  const CommonComponentsDialog({Key? key}) : super(key: key);

  @override
  State<CommonComponentsDialog> createState() => _CommonComponentsDialogState();
}

class _CommonComponentsDialogState extends State<CommonComponentsDialog> {
  // Use a Set to store selected verbs efficiently
  final Set<String> _selectedVerbs = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Install Common Components'),
      content: SizedBox(
        width: double.maxFinite, // Use available width
        // Use a ListView for potentially long lists
        child: ListView.builder(
          shrinkWrap: true, // Make ListView take minimum space
          itemCount: commonComponents.length,
          itemBuilder: (context, index) {
            final component = commonComponents[index];
            final isSelected = _selectedVerbs.contains(component.verb);
            return CheckboxListTile(
              title: Text(component.name),
              subtitle: component.description.isNotEmpty ? Text(component.description) : null,
              value: isSelected,
              onChanged: (bool? value) {
                setState(() {
                  if (value == true) {
                    _selectedVerbs.add(component.verb);
                  } else {
                    _selectedVerbs.remove(component.verb);
                  }
                });
              },
              controlAffinity: ListTileControlAffinity.leading, // Checkbox on the left
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), // Return null on cancel
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedVerbs.isEmpty
              ? null // Disable if nothing is selected
              : () => Navigator.pop(context, _selectedVerbs.toList()), // Return list of selected verbs
          child: const Text('Install Selected'),
        ),
      ],
    );
  }
}