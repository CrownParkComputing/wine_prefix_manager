import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/prefix_models.dart';
import '../models/wine_build.dart';
import '../models/settings.dart';
import '../providers/prefix_provider.dart';
import '../services/build_service.dart';
import '../services/prefix_creation_service.dart';

class PrefixCreationPage extends StatefulWidget {
  // Pass settings if not using a SettingsProvider yet
  final Settings? settings;

  const PrefixCreationPage({Key? key, required this.settings}) : super(key: key);

  @override
  State<PrefixCreationPage> createState() => _PrefixCreationPageState();
}

class _PrefixCreationPageState extends State<PrefixCreationPage> {
  List<BaseBuild> _builds = [];
  BaseBuild? _selectedBuild;
  PrefixType _selectedPrefixType = PrefixType.wine;
  bool _isLoading = false; // Loading state for this page (build fetching, prefix creation)
  String _prefixName = '';
  String _status = ''; // Status messages for this page
  final TextEditingController _prefixNameController = TextEditingController();

  // Service instances needed for this page
  final BuildService _buildService = BuildService();
  final PrefixCreationService _prefixCreationService = PrefixCreationService();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Check if settings are available before fetching builds
    if (widget.settings != null) {
      _fetchBuilds();
    } else {
      setState(() {
        _status = 'Settings not loaded. Please configure settings first.';
      });
    }
  }

  @override
  void dispose() {
    _prefixNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchBuilds() async {
    if (widget.settings == null) {
      setState(() {
        _status = 'Error: Settings not initialized. Please go to Settings tab first.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Fetching available builds...';
    });

    try {
      if (widget.settings == null) {
        throw Exception("Settings are required to fetch builds.");
      }
      final List<BaseBuild> builds = await _buildService.fetchBuilds(widget.settings!); // Pass settings
      if (mounted) {
        setState(() {
          _builds = builds;
          _status = 'Found ${builds.length} builds';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error fetching builds: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadAndCreatePrefix() async {
    if (widget.settings == null) {
       setState(() { _status = 'Settings not loaded.'; });
       return;
    }
    if (_selectedBuild == null) {
      setState(() { _status = 'Please select a build.'; });
      return;
    }
    if (_prefixName.isEmpty) {
      setState(() { _status = 'Please enter a prefix name.'; });
      return;
    }

    // Access provider to check for existing names
    final prefixProvider = context.read<PrefixProvider>();
    if (prefixProvider.prefixes.any((p) => p.name == _prefixName)) {
       setState(() { _status = 'Prefix name "$_prefixName" already exists.'; });
       return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Starting prefix creation...';
    });

    try {
      final newPrefix = await _prefixCreationService.downloadAndCreatePrefix(
        selectedBuild: _selectedBuild!,
        prefixName: _prefixName,
        settings: widget.settings!,
        onStatusUpdate: (status) {
          if (mounted) {
            setState(() { _status = status; });
          }
        },
        onProgressUpdate: (progress) {
          // Optional: Update a progress indicator specific to this page
        },
      );

      if (newPrefix != null && mounted) {
        // Add the new prefix using the provider
        prefixProvider.addCreatedPrefix(newPrefix);
        setState(() {
          _status = prefixProvider.status; // Reflect provider status
          _prefixNameController.clear();
          _prefixName = '';
          _selectedBuild = null; // Reset build selection
        });
        // Saving is handled by the provider
      } else if (mounted) {
         // Service returned null (error), status already updated by service callback
         print('Prefix creation failed (service returned null).');
         // Status should have been updated by the callback, but set a fallback
         if (_status.toLowerCase().contains('starting')) {
            setState(() { _status = 'Prefix creation failed.'; });
         }
      }

    } catch (e) {
       if (mounted) {
          setState(() {
             _status = 'Unexpected error during prefix creation: $e';
          });
       }
       print('Unexpected error calling prefix creation service: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
     // Access provider for checking existing names
     final prefixProvider = context.watch<PrefixProvider>(); // Watch for prefix list changes

     bool checkPrefixExists(String name) {
       return prefixProvider.prefixes.any((p) => p.name == name);
     }

    return Scaffold(
      // No AppBar needed if this page is used within a TabBar/IndexedStack
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card( // Select Prefix Type
                elevation: 3, margin: const EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select Prefix Type', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      SegmentedButton<PrefixType>(
                        segments: const [
                          ButtonSegment<PrefixType>(value: PrefixType.wine, label: Text('Wine'), icon: Icon(Icons.wine_bar)),
                          ButtonSegment<PrefixType>(value: PrefixType.proton, label: Text('Proton'), icon: Icon(Icons.games)),
                        ],
                        selected: {_selectedPrefixType},
                        onSelectionChanged: (Set<PrefixType> newSelection) {
                          setState(() {
                            _selectedPrefixType = newSelection.first;
                            _selectedBuild = null; // Reset build selection
                            // Optionally re-fetch builds if they differ significantly by type,
                            // but current _fetchBuilds gets all types.
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              Card( // Select Build
                elevation: 3, margin: const EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row( // Add refresh button for builds
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [
                           const Text('Select Build', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                           IconButton(
                             icon: const Icon(Icons.refresh),
                             tooltip: 'Refresh Builds',
                             onPressed: _isLoading ? null : () => _fetchBuilds(), // Wrap in anonymous func
                           ),
                         ],
                      ),
                      const SizedBox(height: 16),
                      _isLoading && _builds.isEmpty // Show loading only when initially fetching
                        ? const Center(child: CircularProgressIndicator())
                        : _builds.where((build) => build.type == _selectedPrefixType).isEmpty
                          ? Center(
                              child: Column(
                                children: [
                                  Text('No builds available for ${_selectedPrefixType.name}.'),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _fetchBuilds(), // Wrap in anonymous func
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Refresh Builds'),
                                  ),
                                ],
                              ),
                            )
                          : Container( // Dropdown for builds
                              decoration: BoxDecoration(
                                border: Border.all(color: Theme.of(context).colorScheme.outline),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<BaseBuild>(
                                  value: _selectedBuild,
                                  onChanged: (BaseBuild? newValue) {
                                    setState(() { _selectedBuild = newValue; });
                                  },
                                  hint: const Text('   Select a build'),
                                  isExpanded: true,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  items: _builds
                                      .where((build) => build.type == _selectedPrefixType)
                                      .map((build) => DropdownMenuItem<BaseBuild>(
                                            value: build,
                                            child: Text(build.name),
                                          ))
                                      .toList(),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ),

              Card( // Prefix Name
                elevation: 3, margin: const EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Prefix Name', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _prefixNameController,
                        decoration: InputDecoration(
                          hintText: 'Enter a name for the prefix',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.create_new_folder),
                          errorText: _prefixName.isNotEmpty && checkPrefixExists(_prefixName)
                              ? 'Prefix name already exists'
                              : null,
                        ),
                        onChanged: (value) {
                          setState(() { _prefixName = value; });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),
              SizedBox( // Create Button
                width: double.infinity, height: 50,
                child: ElevatedButton.icon(
                  // Disable if loading, no build selected, name empty, or name exists
                  onPressed: (_isLoading || _selectedBuild == null || _prefixName.isEmpty || checkPrefixExists(_prefixName))
                    ? null
                    : _downloadAndCreatePrefix,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  icon: _isLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary)) : const Icon(Icons.add_circle),
                  label: Text(_isLoading ? 'Creating...' : 'Create Prefix', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),

              // Status Display Area
              if (_isLoading || _status.isNotEmpty)
                 Padding(
                   padding: const EdgeInsets.only(top: 24),
                   child: Card(
                     color: _status.contains('Error') || _status.contains('Failed')
                       ? Theme.of(context).colorScheme.errorContainer
                       : Theme.of(context).colorScheme.primaryContainer,
                     child: Padding(
                       padding: const EdgeInsets.all(12),
                       child: Row(
                         children: [
                           if (_isLoading && !_status.toLowerCase().contains('starting')) // Show spinner only during active work
                              Padding(
                                padding: const EdgeInsets.only(right: 12.0),
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)),
                              )
                           else
                              Icon( // Show icon based on status type
                                _status.contains('Error') || _status.contains('Failed') ? Icons.error : Icons.info,
                                color: _status.contains('Error') || _status.contains('Failed')
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                              ),
                           const SizedBox(width: 12),
                           Expanded(
                             child: Text(
                               _status,
                               style: TextStyle(
                                 color: _status.contains('Error') || _status.contains('Failed')
                                   ? Theme.of(context).colorScheme.onErrorContainer
                                   : Theme.of(context).colorScheme.onPrimaryContainer,
                               ),
                             ),
                           ),
                         ],
                       ),
                     ),
                   ),
                 ),
            ],
          ),
        ),
      ),
    );
  }
}
