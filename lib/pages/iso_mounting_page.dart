import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/prefix_models.dart';
import '../services/iso_mounting_service.dart';
import '../providers/prefix_provider.dart';

class IsoMountingPage extends StatefulWidget {
  const IsoMountingPage({super.key});

  @override
  State<IsoMountingPage> createState() => _IsoMountingPageState();
}

class _IsoMountingPageState extends State<IsoMountingPage> {
  String _statusMessage = '';
  bool _isLoading = false;
  WinePrefix? _selectedPrefix;

  Future<void> _selectAndMountIso() async {
    if (_selectedPrefix == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a prefix first')),
      );
      return;
    }

    final isoService = Provider.of<IsoMountingService>(context, listen: false);

    try {
      // Pick ISO file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['iso', 'img', 'bin', 'cue'],
        dialogTitle: 'Select ISO file to mount',
      );

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      final isoPath = result.files.first.path!;
      
      if (mounted) {
        setState(() {
          _isLoading = true;
          _statusMessage = 'Mounting ISO...';
        });
      }

      final success = await isoService.mountIso(
        prefix: _selectedPrefix!,
        isoPath: isoPath,
        onStatusUpdate: (message) {
          if (mounted) {
            setState(() {
              _statusMessage = message;
            });
          }
        },
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ISO mounted successfully as CD drive D:')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to mount ISO'), 
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error mounting ISO: $e'), 
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '';
        });
      }
    }
  }

  Future<void> _unmountIso(WinePrefix prefix) async {
    final isoService = Provider.of<IsoMountingService>(context, listen: false);

    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _statusMessage = 'Unmounting ISO...';
        });
      }

      final success = await isoService.unmountIso(
        prefix: prefix,
        onStatusUpdate: (message) {
          if (mounted) {
            setState(() {
              _statusMessage = message;
            });
          }
        },
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ISO ejected successfully')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to eject ISO'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error ejecting ISO: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefixProvider = Provider.of<PrefixProvider>(context);
    final isoService = Provider.of<IsoMountingService>(context);
    final prefixes = prefixProvider.prefixes;
    final mountedIsos = isoService.getAllMountedIsos();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ISO/CD Management'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            const Text(
              'Mount ISO Files',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Mount ISO files as virtual CD drives in Wine prefixes',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            
            // No prefixes message
            if (prefixes.isEmpty) ...[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Icon(Icons.folder_off, size: 48),
                      SizedBox(height: 16),
                      Text(
                        'No Wine prefixes found',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text('Create a prefix first to mount ISOs'),
                    ],
                  ),
                ),
              ),
            ],

            // Mount controls
            if (prefixes.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Prefix dropdown
                      DropdownButtonFormField<WinePrefix>(
                        value: _selectedPrefix,
                        decoration: const InputDecoration(
                          labelText: 'Select Wine Prefix',
                          border: OutlineInputBorder(),
                        ),
                        items: prefixes.map((prefix) {
                          return DropdownMenuItem(
                            value: prefix,
                            child: Text(prefix.name),
                          );
                        }).toList(),
                        onChanged: _isLoading ? null : (prefix) {
                          setState(() {
                            _selectedPrefix = prefix;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Mount button
                      ElevatedButton.icon(
                        onPressed: (_isLoading || _selectedPrefix == null) 
                            ? null 
                            : _selectAndMountIso,
                        icon: _isLoading 
                            ? const SizedBox(
                                width: 16, 
                                height: 16, 
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_circle_outline),
                        label: const Text('Mount ISO'),
                      ),
                      
                      // Status message
                      if (_statusMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Text(
                            _statusMessage,
                            style: const TextStyle(color: Colors.blue),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            
            // Mounted ISOs section
            const Text(
              'Currently Mounted ISOs',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            // Mounted ISOs list
            if (mountedIsos.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Icon(Icons.disc_full, size: 48, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No ISOs currently mounted',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Mount an ISO to see it here',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...mountedIsos.map((mountedIso) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.album),
                  title: Text(mountedIso.prefix.name),
                  subtitle: Text('ISO: ${mountedIso.isoPath.split('/').last}'),
                  trailing: IconButton(
                    onPressed: _isLoading 
                        ? null 
                        : () => _unmountIso(mountedIso.prefix),
                    icon: const Icon(Icons.eject),
                    tooltip: 'Eject ISO',
                  ),
                ),
              )).toList(),
          ],
        ),
      ),
    );
  }
} 