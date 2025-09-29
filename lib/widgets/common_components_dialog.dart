import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
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
  bool _hasVcRun2019 = false;
  bool _hasVcRun2022 = false;
  bool _hasVcRedistX64 = false;
  bool _hasVcRedistX86 = false;
  bool _hasVcRedistLegacy = false;
  List<String> _winetricksComponents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkDirectXComponents();
  }
  
  Future<void> _checkDirectXComponents() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking installed components...';
    });
    
    try {
      final componentStatus = await _prefixService.checkInstalledComponents(widget.prefix);
      
      if (mounted) {
        setState(() {
          _hasDXVK = componentStatus['dxvk'] ?? false;
          _hasVKD3D = componentStatus['vkd3d'] ?? false;
          _hasVcRun2019 = componentStatus['vcrun2019'] ?? false;
          _hasVcRun2022 = componentStatus['vcrun2022'] ?? false;
          _hasVcRedistX64 = componentStatus['vcredist_x64'] ?? false;
          _hasVcRedistX86 = componentStatus['vcredist_x86'] ?? false;
          _hasVcRedistLegacy = componentStatus['vcredist_legacy'] ?? false;
          _winetricksComponents = List<String>.from(componentStatus['winetricks_list'] ?? []);
          _isLoading = false;
          
          // Build status message
          final dxvkStatus = _hasDXVK ? 'Installed ✓' : 'Not Installed ✕';
          final vkd3dStatus = _hasVKD3D ? 'Installed ✓' : 'Not Installed ✕';
          final vcppStatus = (_hasVcRedistX64 || _hasVcRedistX86 || _hasVcRedistLegacy || _hasVcRun2019 || _hasVcRun2022) ? 'Some Installed ✓' : 'None Installed ✕';
          
          _statusMessage = 'DXVK: $dxvkStatus, VKD3D: $vkd3dStatus, VC++: $vcppStatus';
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
  
  /// Gets the Proton wine executable path for a Proton prefix
  Future<String?> _getProtonWineExecutable(WinePrefix prefix) async {
    if (prefix.type != PrefixType.proton) return null;
    
    try {
      // Try to find the proton script first
      final protonScript = path.join(prefix.wineBuildPath, 'proton');
      if (await File(protonScript).exists()) {
        return protonScript;
      }
      
      // Try proton.sh as alternative
      final protonShScript = path.join(prefix.wineBuildPath, 'proton.sh');
      if (await File(protonShScript).exists()) {
        return protonShScript;
      }
      
      // For Kronek/Wine-Proton builds, look for wine executable
      final wineExecutable = path.join(prefix.wineBuildPath, 'bin', 'wine');
      if (await File(wineExecutable).exists()) {
        return wineExecutable;
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// Gets the Proton environment variables for a Proton prefix
  Future<Map<String, String>?> _getProtonEnvironment(WinePrefix prefix) async {
    if (prefix.type != PrefixType.proton) return null;
    
    final buildPath = prefix.wineBuildPath;
    
    return {
      'WINEPREFIX': prefix.path,
      'STEAM_COMPAT_DATA_PATH': prefix.path,
      'STEAM_COMPAT_CLIENT_INSTALL_PATH': Platform.environment['HOME'] ?? '/tmp',
      'PROTON_LOG': '1',
      'PATH': '$buildPath/bin:$buildPath/files/bin:${Platform.environment['PATH']}',
      'LD_LIBRARY_PATH': '$buildPath/lib64:$buildPath/lib:$buildPath/files/lib64:$buildPath/files/lib:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
      'WINEDLLOVERRIDES': 'winemenubuilder.exe=d',
    };
  }

  Future<void> _installComponent(Future<bool> Function(WinePrefix, Settings, {Function(String)? progressCallback, String? customWineExecutable, Map<String, String>? customEnv}) installFunction) async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _statusMessage = 'Starting installation...';
    });

    try {
      // Get proper wine executable and environment for Proton prefixes
      String? customWineExecutable;
      Map<String, String>? customEnv;
      
      if (widget.prefix.type == PrefixType.proton) {
        customWineExecutable = await _getProtonWineExecutable(widget.prefix);
        customEnv = await _getProtonEnvironment(widget.prefix);
      }
      
      final success = await installFunction(
        widget.prefix,
        widget.settings,
        progressCallback: _updateStatus,
        customWineExecutable: customWineExecutable,
        customEnv: customEnv,
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

  Future<void> _installVcRedistAllInOne() async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _statusMessage = 'Installing TechPowerUp Visual C++ All-in-One package...';
    });

    try {
      final success = await _installer.installVcRedistAllInOne(
        widget.prefix,
        widget.settings,
        progressCallback: _updateStatus,
      );

      if (mounted) {
        setState(() {
          _statusMessage = success 
            ? 'TechPowerUp Visual C++ All-in-One package installed successfully!' 
            : 'TechPowerUp Visual C++ All-in-One installation failed. Check logs.';
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
          _statusMessage = 'Error during VC++ All-in-One installation: $e';
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

  // Add methods for Winetricks-based VC++ installation
  Future<void> _installVcRun2019() async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _statusMessage = 'Installing VC++ 2019 via Winetricks...';
    });

    try {
      final success = await _installer.installVcRunViaTricks2019(
        widget.prefix,
        widget.settings,
        progressCallback: _updateStatus,
      );

      if (mounted) {
        setState(() {
          _statusMessage = success 
            ? 'VC++ 2019 (Winetricks) installed successfully!' 
            : 'VC++ 2019 (Winetricks) installation failed. Check logs.';
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
          _statusMessage = 'Error during VC++ 2019 (Winetricks) installation: $e';
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

  Future<void> _installVcRun2022() async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _statusMessage = 'Installing VC++ 2022 via Winetricks...';
    });

    try {
      final success = await _installer.installVcRunViaTricks2022(
        widget.prefix,
        widget.settings,
        progressCallback: _updateStatus,
      );

      if (mounted) {
        setState(() {
          _statusMessage = success 
            ? 'VC++ 2022 (Winetricks) installed successfully!' 
            : 'VC++ 2022 (Winetricks) installation failed. Check logs.';
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
          _statusMessage = 'Error during VC++ 2022 (Winetricks) installation: $e';
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

  Future<void> _installVcRedistComprehensive() async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _statusMessage = 'Starting comprehensive VC++ installation (2005-2022)...';
    });

    try {
      // Get proper wine executable and environment for Proton prefixes
      String? customWineExecutable;
      Map<String, String>? customEnv;
      
      if (widget.prefix.type == PrefixType.proton) {
        customWineExecutable = await _getProtonWineExecutable(widget.prefix);
        customEnv = await _getProtonEnvironment(widget.prefix);
      }
      
      final success = await _installer.installAllVcppRedistributablesComprehensive(
        widget.prefix,
        widget.settings,
        progressCallback: _updateStatus,
        customWineExecutable: customWineExecutable,
        customEnv: customEnv,
      );

      if (mounted) {
        setState(() {
          _statusMessage = success 
            ? 'All Visual C++ Redistributables (2005-2022) installed successfully!' 
            : 'VC++ comprehensive installation failed. Check logs.';
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
          _statusMessage = 'Error during comprehensive VC++ installation: $e';
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
        height: 500, // Set a fixed height to prevent overflow
        child: SingleChildScrollView(
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
                          const SizedBox(height: 8),
                          Text(
                            'Visual C++ Redistributables:',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                _hasVcRedistX64 ? Icons.check_circle : Icons.cancel,
                                color: _hasVcRedistX64 ? Colors.green : Colors.red,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              const Text('VC++ x64 (Direct Install)', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                _hasVcRedistX86 ? Icons.check_circle : Icons.cancel,
                                color: _hasVcRedistX86 ? Colors.green : Colors.red,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              const Text('VC++ x86 (Direct Install)', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                _hasVcRun2019 ? Icons.check_circle : Icons.cancel,
                                color: _hasVcRun2019 ? Colors.green : Colors.red,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              const Text('vcrun2019 (Winetricks)', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                _hasVcRun2022 ? Icons.check_circle : Icons.cancel,
                                color: _hasVcRun2022 ? Colors.green : Colors.red,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              const Text('vcrun2022 (Winetricks)', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                _hasVcRedistLegacy ? Icons.check_circle : Icons.cancel,
                                color: _hasVcRedistLegacy ? Colors.green : Colors.red,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              const Text('Legacy VC++ (2005-2013)', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                          if (_winetricksComponents.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Other Winetricks components: ${_winetricksComponents.take(3).join(', ')}${_winetricksComponents.length > 3 ? '...' : ''}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
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
              'Visual C++ Redistributables (All Versions)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Required for many games and applications.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            
            // Comprehensive VC++ installer (single, reliable option)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Install All Visual C++ Redistributables (2005-2022)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.tertiary,
                    foregroundColor: Theme.of(context).colorScheme.onTertiary,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isInstalling ? null : _installVcRedistComprehensive,
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            Text(
              'This will install Microsoft Visual C++ 2015-2022 Redistributables (x64 and x86) and create comprehensive registry entries for maximum compatibility with games requiring VC++ 2005-2022.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            
            const SizedBox(height: 16),
            
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