import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/wine_build.dart';
import '../models/settings.dart';
import '../providers/prefix_provider.dart';
import '../services/build_service.dart';
import '../services/prefix_creation_service.dart';
import '../services/log_service.dart'; // Import LogService
import '../models/prefix_models.dart'; // Import PrefixType

class PrefixCreationForm extends StatefulWidget {
  final Settings? settings;

  const PrefixCreationForm({Key? key, required this.settings}) : super(key: key);

  @override
  State<PrefixCreationForm> createState() => _PrefixCreationFormState();
}

class _PrefixCreationFormState extends State<PrefixCreationForm> {
  List<BaseBuild> _builds = [];
  BaseBuild? _selectedBuild;
  PrefixType _selectedPrefixType = PrefixType.wine;
  bool _isLoading = false; // Loading state for this form
  String _prefixName = '';
  String _status = ''; // Status messages for this form
  final TextEditingController _prefixNameController = TextEditingController();

  // Service instances needed for this form
  final BuildService _buildService = BuildService();
  final PrefixCreationService _prefixCreationService = PrefixCreationService();
  final LogService _logService = LogService(); // Get instance

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (widget.settings != null) {
      _fetchBuilds();
    } else {
      _updateStatus('Settings not loaded. Please configure settings first.', isError: true);
    }
  }

  @override
  void dispose() {
    _prefixNameController.dispose();
    super.dispose();
  }

  void _updateStatus(String message, {bool isError = false}) {
     if (mounted) {
       setState(() {
         _status = message;
       });
     }
     _logService.log(message, isError ? LogLevel.error : LogLevel.info);
  }

  Future<void> _fetchBuilds() async {
    if (widget.settings == null) {
      _updateStatus('Error: Settings not initialized.', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Fetching available builds...';
    });
    _logService.log('Fetching available builds...');

    try {
      final List<BaseBuild> builds = await _buildService.fetchBuilds(widget.settings!);
      if (mounted) {
        setState(() {
          _builds = builds;
          _status = 'Found ${builds.length} builds';
        });
        _logService.log('Found ${builds.length} builds');
      }
    } catch (e) {
      _updateStatus('Error fetching builds: $e', isError: true);
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
       _updateStatus('Settings not loaded.', isError: true);
       return;
    }
    // Requires a build only if not Gaming type
    if (_selectedPrefixType != PrefixType.gaming && _selectedBuild == null) {
      _updateStatus('Please select a build.', isError: true);
      return;
    }
    // Prevent creation using installed builds
    if (_selectedBuild != null && _selectedBuild!.installPath != null) {
       _updateStatus('Creating prefixes from installed Steam Proton builds is not yet supported.', isError: true);
       return;
    }
    if (_prefixName.isEmpty) {
      _updateStatus('Please enter a prefix name.', isError: true);
      return;
    }

    final prefixProvider = context.read<PrefixProvider>();
    if (prefixProvider.prefixes.any((p) => p.name == _prefixName)) {
       _updateStatus('Prefix name "$_prefixName" already exists.', isError: true);
       return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Starting prefix creation...';
    });
    _logService.log('Starting prefix creation for "$_prefixName"...');


    try {
      // Pass the explicitly selected prefix type (_selectedPrefixType)
      // The service will use this type when creating the WinePrefix object.
      final newPrefix = await _prefixCreationService.downloadAndCreatePrefix(
        // For Gaming type, selectedBuild might be null, handle this in the service
        selectedBuild: _selectedBuild, // Pass the selected build (can be null for Gaming)
        prefixName: _prefixName,
        settings: widget.settings!,
        prefixType: _selectedPrefixType, // Pass the type selected in the UI
        onStatusUpdate: (status) {
          // Update local status, don't log here as service might log too
          if (mounted) setState(() { _status = status; });
        },
        onProgressUpdate: (progress) {
          // Optional: Update a progress indicator if needed
        },
      );

      if (newPrefix != null && mounted) {
        prefixProvider.addCreatedPrefix(newPrefix); // Add via provider
        _updateStatus('Prefix "$_prefixName" created successfully!'); // Update local status
        setState(() {
          _prefixNameController.clear();
          _prefixName = '';
          _selectedBuild = null;
        });
      } else if (mounted) {
         // Error handled by service callback or exception below
         if (!_status.toLowerCase().contains('error') && !_status.toLowerCase().contains('failed')) {
            _updateStatus('Prefix creation failed.', isError: true);
         }
      }

    } catch (e) {
       _updateStatus('Unexpected error during prefix creation: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Helper to get display name for PrefixType
  String _getPrefixTypeName(PrefixType type) {
    switch (type) {
      case PrefixType.wine:
        return 'Wine';
      case PrefixType.proton:
        return 'Proton';
      // case PrefixType.protonExperimental: // Removed case
      //   return 'Proton Exp.';
      case PrefixType.gaming:
        return 'Gaming';
    }
  }

  // Helper to get icon for PrefixType
  IconData _getPrefixTypeIcon(PrefixType type) {
    switch (type) {
      case PrefixType.wine:
        return Icons.wine_bar;
      case PrefixType.proton:
        return Icons.games; // Standard Proton icon
      // case PrefixType.protonExperimental: // Removed case
      //   return Icons.science;
      case PrefixType.gaming:
        return Icons.sports_esports; // Gaming icon
    }
  }

  @override
  Widget build(BuildContext context) {
     final prefixProvider = context.watch<PrefixProvider>(); // Needed for name check

     bool checkPrefixExists(String name) {
       return prefixProvider.prefixes.any((p) => p.name == name);
     }

     // --- Filter builds based on selected type ---
     // Now directly filter based on the selected UI type
     // Only filter if not Gaming type
     final filteredBuilds = _selectedPrefixType == PrefixType.gaming
         ? <BaseBuild>[] // No builds needed for Gaming type
         : _builds.where((build) => build.type == _selectedPrefixType).toList();

     // Ensure selected build is valid for the current type filter
     // Check against the actual selected type, not the filtered type
     if (_selectedBuild != null && _selectedBuild!.type != _selectedPrefixType) {
        // Use a post-frame callback to safely reset _selectedBuild after the build phase
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _selectedBuild = null;
            });
          }
        });
     }
     // --- End Filter builds ---

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Select Prefix Type ---
            Card(
              elevation: 3, margin: const EdgeInsets.only(bottom: 24),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select Prefix Type', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    SegmentedButton<PrefixType>(
                      // Filter out the removed type before mapping
                      segments: PrefixType.values
                          // .where((type) => type != PrefixType.protonExperimental) // No longer needed as enum value is removed
                          .map((type) => ButtonSegment<PrefixType>(
                        value: type,
                        label: Text(_getPrefixTypeName(type)),
                        icon: Icon(_getPrefixTypeIcon(type)),
                      )).toList(),
                      selected: {_selectedPrefixType},
                      onSelectionChanged: (Set<PrefixType> newSelection) {
                        setState(() {
                          _selectedPrefixType = newSelection.first;
                          // _selectedBuild = null; // Resetting here can cause issues during build phase
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            // --- Select Build ---
            Card(
              // Hide build selection if Gaming type is selected
              child: _selectedPrefixType == PrefixType.gaming ? const SizedBox.shrink() : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                       children: [
                         // Dynamically update title based on selected type
                         Text('Select ${_getPrefixTypeName(_selectedPrefixType)} Build', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                         IconButton(
                           icon: const Icon(Icons.refresh),
                           tooltip: 'Refresh Builds',
                           onPressed: _isLoading ? null : _fetchBuilds,
                         ),
                       ],
                    ),
                    const SizedBox(height: 16),
                    _isLoading && _builds.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : filteredBuilds.isEmpty
                        ? Center(
                            child: Column(
                              children: [
                                Text('No builds available for ${_getPrefixTypeName(_selectedPrefixType)}.'),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _fetchBuilds,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Refresh Builds'),
                                ),
                              ],
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(context).colorScheme.outline),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<BaseBuild>(
                                value: _selectedBuild,
                                onChanged: (BaseBuild? newValue) {
                                  // Prevent selecting installed builds for creation
                                  if (newValue != null && newValue.installPath != null) {
                                     _updateStatus('Cannot create prefix from installed build yet.', isError: true);
                                     return; // Don't update selection
                                  }
                                  setState(() { _selectedBuild = newValue; });
                                },
                                hint: Text('   Select a ${_getPrefixTypeName(_selectedPrefixType)} build'),
                                isExpanded: true,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                items: filteredBuilds
                                    .map((build) {
                                       final bool isInstalled = build.installPath != null;
                                       final String displayName = isInstalled ? "${build.name} (Installed)" : build.name;
                                       return DropdownMenuItem<BaseBuild>(
                                          value: build,
                                          // Disable installed builds for now
                                          enabled: !isInstalled,
                                          child: Text(
                                             displayName,
                                             style: TextStyle(
                                                color: isInstalled ? Theme.of(context).disabledColor : null,
                                             ),
                                          ),
                                        );
                                    })
                                    .toList(),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),

            // --- Prefix Name ---
            Card(
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
                        // Use setState to update _prefixName and trigger rebuild for errorText check
                        setState(() { _prefixName = value.trim(); });
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // --- Create Button ---
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                // Disable button if selected build is installed
                // Adjust condition for Gaming type (doesn't need _selectedBuild)
                onPressed: (_isLoading ||
                          (_selectedPrefixType != PrefixType.gaming && (_selectedBuild == null || _selectedBuild!.installPath != null)) || // Check build only if not Gaming
                          _prefixName.isEmpty || checkPrefixExists(_prefixName)) ? null
                  : _downloadAndCreatePrefix,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                icon: _isLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary)) : const Icon(Icons.add_circle),
                label: Text(_isLoading ? 'Creating...' : 'Create Prefix', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            // --- Status Display Area ---
            if (_status.isNotEmpty)
               Padding(
                 padding: const EdgeInsets.only(top: 24),
                 child: Card(
                   color: _status.contains('Error') || _status.contains('Failed') || _status.contains('already exists') || _status.contains('not yet supported')
                     ? Theme.of(context).colorScheme.errorContainer
                     : Theme.of(context).colorScheme.primaryContainer,
                   child: Padding(
                     padding: const EdgeInsets.all(12),
                     child: Row(
                       children: [
                         if (_isLoading && !_status.toLowerCase().contains('starting'))
                             Padding(
                               padding: const EdgeInsets.only(right: 12.0),
                               child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)),
                             )
                         else
                             Icon(
                               _status.contains('Error') || _status.contains('Failed') || _status.contains('already exists') || _status.contains('not yet supported') ? Icons.error : Icons.info,
                               color: _status.contains('Error') || _status.contains('Failed') || _status.contains('already exists') || _status.contains('not yet supported')
                                 ? Theme.of(context).colorScheme.error
                                 : Theme.of(context).colorScheme.primary,
                             ),
                         const SizedBox(width: 12),
                         Expanded(
                           child: Text(
                             _status,
                             style: TextStyle(
                               color: _status.contains('Error') || _status.contains('Failed') || _status.contains('already exists') || _status.contains('not yet supported')
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
    );
  }
}