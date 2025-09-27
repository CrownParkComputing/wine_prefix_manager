import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../services/wine_component_installer.dart';
import '../services/prefix_management_service.dart'; // Add service to check components and install to Proton

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
  final PrefixManagementService _prefixService = PrefixManagementService(); 
  String _statusMessage = 'Select a component to install.';
  bool _isInstalling = false;
  bool _hasDXVK = false;
  bool _hasVKD3D = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkDirectXComponents();
  }
  
  Future<void> _checkDirectXComponents() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking DirectX components...';
    });
    
    try {
      final componentStatus = await _prefixService.checkDirectXSupportComponents(widget.prefix);
      
      if (mounted) {
        setState(() {
          _hasDXVK = componentStatus['dxvk'] ?? false;
          _hasVKD3D = componentStatus['vkd3d'] ?? false;
          _isLoading = false;
          _statusMessage = 'DXVK: ${_hasDXVK ? 'Installed ✓' : 'Not Installed ✕'}, '
                         'VKD3D (DX12): ${_hasVKD3D ? 'Installed ✓' : 'Not Installed ✕'}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Error checking components: $e';
        });
      }
    }
  }

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
            backgroundColor: success ? Colors.green : Colors.orange, // Use standard orange instead of warning
          ),
        );
        
        // Check components again after installation
        await _checkDirectXComponents();
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
  
  Future<void> _installVkd3dToProton() async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _statusMessage = 'Starting VKD3D installation for Proton...';
    });

    try {
      final success = await _prefixService.installVkd3dToProtonPrefix(
        widget.prefix,
        progressCallback: _updateStatus,
      );

      if (mounted) {
        setState(() {
          _statusMessage = success 
            ? 'VKD3D installation to Proton successful!' 
            : 'VKD3D installation to Proton failed. Check logs.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_statusMessage),
            backgroundColor: success ? Colors.green : Colors.orange, // Use standard orange instead of warning
          ),
        );
        
        // Check components again after installation
        await _checkDirectXComponents();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error during VKD3D installation: $e';
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

  // Add a new method to handle combined component installation
  Future<void> _installCompleteDirectXSupport() async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _statusMessage = 'Installing complete DirectX support...';
    });

    try {
      final success = await _prefixService.installCompleteDirectXSupport(
        widget.prefix,
        widget.settings,
        progressCallback: _updateStatus,
      );

      if (mounted) {
        setState(() {
          _statusMessage = success 
            ? 'Complete DirectX support installed successfully!' 
            : 'Complete DirectX support installation failed. Check logs.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_statusMessage),
            backgroundColor: success ? Colors.green : Colors.orange,
          ),
        );
        
        // Check components again after installation
        await _checkDirectXComponents();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error during complete DirectX support installation: $e';
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

  // Add methods for Visual C++ Redistributable installation
  Future<void> _installVcRedistX86() async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _statusMessage = 'Installing Visual C++ Redistributable (x86)...';
    });

    try {
      final success = await _installer.installVcRedistX86(
        widget.prefix,
        widget.settings,
        progressCallback: _updateStatus,
      );

      if (mounted) {
        setState(() {
          _statusMessage = success 
            ? 'Visual C++ Redistributable (x86) installed successfully!' 
            : 'Visual C++ Redistributable (x86) installation failed. Check logs.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_statusMessage),
            backgroundColor: success ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error during VC++ x86 installation: $e';
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

  Future<void> _installVcRedistX64() async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _statusMessage = 'Installing Visual C++ Redistributable (x64)...';
    });

    try {
      final success = await _installer.installVcRedistX64(
        widget.prefix,
        widget.settings,
        progressCallback: _updateStatus,
      );

      if (mounted) {
        setState(() {
          _statusMessage = success 
            ? 'Visual C++ Redistributable (x64) installed successfully!' 
            : 'Visual C++ Redistributable (x64) installation failed. Check logs.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_statusMessage),
            backgroundColor: success ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error during VC++ x64 installation: $e';
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

  Future<void> _installLegacyGameDependencies() async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _statusMessage = 'Installing legacy game dependencies...';
    });

    try {
      final success = await _installer.installLegacyGameDependencies(
        widget.prefix,
        widget.settings,
        progressCallback: _updateStatus,
      );

      if (mounted) {
        setState(() {
          _statusMessage = success 
            ? 'Legacy game dependencies installed successfully!' 
            : 'Legacy game dependencies installation failed. Check logs.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_statusMessage),
            backgroundColor: success ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error during legacy game dependencies installation: $e';
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
    final bool isKronekProton = isProtonPrefix && 
      (widget.prefix.wineBuildPath.contains('wine-proton') || 
       widget.prefix.wineBuildPath.contains('Kronek'));
    const String protonTooltip = 'Not needed for Proton-GE prefixes (already included)';

    return AlertDialog(
      title: Text('Install Components for "${widget.prefix.name}"'),
      content: SizedBox(
        width: 450, // Increased width for more space 
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Install necessary components like DXVK, VKD3D-Proton, or Visual C++ Redistributables into the selected Wine prefix.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            
            // Status cards for component installation status
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Status',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _hasDXVK ? Icons.check_circle : Icons.cancel,
                                color: _hasDXVK ? Colors.green : Colors.red,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              const Text('DXVK (DirectX 9/10/11 → Vulkan)'),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                _hasVKD3D ? Icons.check_circle : Icons.cancel,
                                color: _hasVKD3D ? Colors.green : Colors.red,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              const Text('VKD3D-Proton (DirectX 12 → Vulkan)'),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 16),
            if (isProtonPrefix && !isKronekProton)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  'Note: Manual installation is usually not needed for Proton-GE prefixes as they include these components.',
                  style: TextStyle(color: Theme.of(context).colorScheme.secondary),
                ),
              ),
            
            if (isKronekProton)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  'Kronek Proton detected: You may need to install VKD3D separately for DirectX 12 support.',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              
            // Combined DirectX installation button (prominent, always available)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.bolt),
                  label: const Text('Install Complete DirectX Support (DXVK + VKD3D)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isInstalling ? null : _installCompleteDirectXSupport,
                ),
              ),
            ),
            
            const Text('Or install components individually:', style: TextStyle(fontSize: 12)),
              
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Tooltip(
                  message: isProtonPrefix && !isKronekProton ? protonTooltip : 'Install latest DXVK',
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Install DXVK'),
                    onPressed: _isInstalling || (isProtonPrefix && !isKronekProton)
                        ? null // Disable if installing or if it's a Proton-GE prefix
                        : () => _installComponent(_installer.installDxvk),
                  ),
                ),
                Tooltip(
                  message: isProtonPrefix && !isKronekProton ? protonTooltip : 'Install latest VKD3D-Proton',
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Install VKD3D'),
                    onPressed: _isInstalling || (isProtonPrefix && !isKronekProton)
                        ? null // Disable if installing or if it's a Proton-GE prefix
                        : () => _installComponent(_installer.installVkd3d),
                  ),
                ),
              ],
            ),
            
            // Special button for Kronek Proton for VKD3D
            if (isKronekProton)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.settings),
                    label: const Text('Install VKD3D to Kronek Proton'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    onPressed: _isInstalling ? null : _installVkd3dToProton,
                  ),
                ),
              ),
              
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            
            // Visual C++ Redistributables Section
            Text(
              'Visual C++ Redistributables (2015-2022)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Required for many games and applications. Install x86 for legacy 32-bit games.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('VC++ x86', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                      foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                    ),
                    onPressed: _isInstalling ? null : _installVcRedistX86,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('VC++ x64', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                      foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                    ),
                    onPressed: _isInstalling ? null : _installVcRedistX64,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Legacy Game Dependencies Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.sports_esports),
                label: const Text('Install Legacy Game Dependencies'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                ),
                onPressed: _isInstalling ? null : _installLegacyGameDependencies,
              ),
            ),
            
            const SizedBox(height: 8),
            Text(
              'Installs VC++ x86, DirectPlay, DirectSound, MFC42, and older VC++ runtimes for legacy games like Tiger Woods PGA TOUR 06.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
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
        TextButton(
          onPressed: _isInstalling ? null : _checkDirectXComponents,
          child: const Text('Refresh Status'),
        ),
      ],
    );
  }
}