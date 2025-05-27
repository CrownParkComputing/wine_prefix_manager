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
  final PrefixType? initialPrefixType; // Added parameter for initial tab selection
  final VoidCallback? onSuccess; // <<<< Added this

  const PrefixCreationForm({
    Key? key, 
    required this.settings,
    this.initialPrefixType, // Optional parameter
    this.onSuccess, // <<<< Added this
  }) : super(key: key);

  @override
  State<PrefixCreationForm> createState() => _PrefixCreationFormState();
}

class _PrefixCreationFormState extends State<PrefixCreationForm> with TickerProviderStateMixin {
  List<BaseBuild> _builds = [];
  BaseBuild? _selectedBuild;
  bool _isLoading = false; // Loading state for this form
  String _prefixName = '';
  String _status = 'Ready'; // Status messages for this form
  double _progress = 0.0; // Added for progress bar
  String _selectedArchitecture = 'win64'; // Added for architecture selection, default to 64-bit
  final TextEditingController _prefixNameController = TextEditingController();
  TabController? _prefixTabController;
  PrefixType _selectedPrefixType = PrefixType.wine; // Changed from custom to wine

  // Service instances needed for this form
  final BuildService _buildService = BuildService();
  final PrefixCreationService _prefixCreationService = PrefixCreationService();
  final LogService _logService = LogService(); // Get instance

  @override
  void initState() {
    super.initState();
    
    // Only create the TabController if we're not inside CreatePrefixPage
    if (widget.initialPrefixType == null) {
      _prefixTabController = TabController(length: 2, vsync: this);
      _prefixTabController!.addListener(_updateSelectedType);
    } else {
      // If we're in CreatePrefixPage, set the selected type directly
      _selectedPrefixType = widget.initialPrefixType!;
    }
    
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
    // Only dispose the TabController if it was created
    if (_prefixTabController != null) {
      _prefixTabController!.dispose();
    }
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

  Future<void> _downloadAndCreatePrefix(PrefixType prefixType) async {
    if (widget.settings == null) {
       _updateStatus('Settings not loaded.', isError: true);
       return;
    }
    
    // Require a build for all prefix types
    if (_selectedBuild == null) {
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
      _progress = 0.0; // Reset progress
    });
    _logService.log('Starting prefix creation for "$_prefixName"...');

    // Determine architecture to pass. Proton defaults to win64.
    final String architectureToPass = (prefixType == PrefixType.proton) ? 'win64' : _selectedArchitecture;

    try {
      // Pass the explicitly selected prefix type and architecture
      final newPrefix = await _prefixCreationService.downloadAndCreatePrefix(
        selectedBuild: _selectedBuild,
        prefixName: _prefixName,
        settings: widget.settings!,
        prefixType: prefixType, 
        architecture: architectureToPass, // Pass selected or defaulted architecture
        onStatusUpdate: (status) {
          if (mounted) setState(() { _status = status; });
        },
        onProgressUpdate: (progress) {
          if (mounted) setState(() { _progress = progress; });
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
        widget.onSuccess?.call(); // <<<< Added this call
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefixProvider = context.watch<PrefixProvider>(); // Needed for name check

    bool checkPrefixExists(String name) {
      return prefixProvider.prefixes.any((p) => p.name == name);
    }

    // If initialPrefixType is specified, return only the specific tab content
    if (widget.initialPrefixType != null) {
      switch (widget.initialPrefixType!) {
        case PrefixType.wine:
          return _buildWinePrefixTab(checkPrefixExists);
        case PrefixType.proton:
          return _buildProtonPrefixTab(checkPrefixExists);
      }
    } else {
      // When used standalone (not in CreatePrefixPage), show our own tabs
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Create New Prefix'),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.wine_bar), text: 'Wine'),
                Tab(icon: Icon(Icons.games), text: 'Proton'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _buildWinePrefixTab(checkPrefixExists),
              _buildProtonPrefixTab(checkPrefixExists),
            ],
          ),
        ),
      );
    }
  }
  
  Widget _buildWinePrefixTab(bool Function(String) checkPrefixExists) {
    // Filter builds for Wine initially (will be further filtered by architecture)
    final baseWineBuilds = _builds.where((build) => build.type == PrefixType.wine).toList();

    // Further filter by selected architecture
    final filteredWineBuilds = baseWineBuilds
        .where((build) => build.architecture == _selectedArchitecture || build.architecture == null) // Allow builds with matching arch or no specified arch
        .toList();

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Architecture Selection for Wine (Moved to the top)
            Card(
              elevation: 3, margin: const EdgeInsets.only(bottom: 24),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select Architecture', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          // labelText: 'Architecture', // Already in Card Title
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                        ),
                        value: _selectedArchitecture,
                        items: const [
                          DropdownMenuItem(value: 'win64', child: Text('64-bit (win64)')),
                          DropdownMenuItem(value: 'win32', child: Text('32-bit (win32)')),
                        ],
                        onChanged: (String? newValue) {
                          if (newValue != null && newValue != _selectedArchitecture) {
                            setState(() {
                              _selectedArchitecture = newValue;
                              // Reset selected build if it's not compatible with the new architecture
                              if (_selectedBuild != null && _selectedBuild!.architecture != null && _selectedBuild!.architecture != _selectedArchitecture) {
                                _selectedBuild = null;
                              }
                            });
                          }
                        },
                      ),
                    ]
                ),
              ),
            ),

            // Build Selection Card
            Card(
              elevation: 3, margin: const EdgeInsets.only(bottom: 24),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Select Wine Build', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      : filteredWineBuilds.isEmpty
                        ? Center(
                            child: Column(
                              children: [
                                Text('No Wine builds available for $_selectedArchitecture.'),
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
                                value: _selectedBuild?.type == PrefixType.wine && (_selectedBuild?.architecture == _selectedArchitecture || _selectedBuild?.architecture == null) 
                                      ? _selectedBuild 
                                      : null,
                                onChanged: (BaseBuild? newValue) {
                                  if (newValue != null && newValue.installPath != null) {
                                    _updateStatus('Cannot create prefix from installed build yet.', isError: true);
                                    return;
                                  }
                                  setState(() { _selectedBuild = newValue; });
                                },
                                hint: const Text('   Select a Wine build'),
                                isExpanded: true,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                items: filteredWineBuilds
                                    .map((build) {
                                       final bool isInstalled = build.installPath != null;
                                       final String displayName = isInstalled ? "${build.getDisplayName} (Installed)" : build.getDisplayName;
                                       return DropdownMenuItem<BaseBuild>(
                                          value: build,
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

            // Prefix Name Card
            Card(
              elevation: 3, margin: const EdgeInsets.only(bottom: 24),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Wine Prefix Name', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                        setState(() { _prefixName = value.trim(); });
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Create Button
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: (_isLoading || _selectedBuild?.type != PrefixType.wine || _prefixName.isEmpty || checkPrefixExists(_prefixName)) 
                  ? null
                  : () => _downloadAndCreatePrefix(PrefixType.wine),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                icon: _isLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary)) : const Icon(Icons.add_circle),
                label: Text(_isLoading ? 'Creating...' : 'Create Wine Prefix', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            // Status and Progress Area
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_status, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _progress > 0 ? _progress : null, backgroundColor: Colors.grey[300]),
                  ],
                ),
              )
            else if (_status != 'Ready' && _status.isNotEmpty) // Show status even if not loading, unless it's just "Ready"
              Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Text(_status, 
                  style: TextStyle(
                    color: _status.toLowerCase().contains('error') || _status.toLowerCase().contains('failed') 
                        ? Theme.of(context).colorScheme.error 
                        : null
                  )
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProtonPrefixTab(bool Function(String) checkPrefixExists) {
    // Filter builds for Proton
    final protonBuilds = _builds.where((build) => build.type == PrefixType.proton).toList();
    
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Build Selection Card
            Card(
              elevation: 3, margin: const EdgeInsets.only(bottom: 24),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Select Proton Build', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Refresh Builds',
                          onPressed: _isLoading ? null : _fetchBuilds,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Add info message for Proton builds
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        'Both GE-Proton and Kronek Proton builds are available for selection.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.secondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    _isLoading && _builds.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : protonBuilds.isEmpty
                        ? Center(
                            child: Column(
                              children: [
                                const Text('No Proton builds available.'),
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
                                value: _selectedBuild?.type == PrefixType.proton ? _selectedBuild : null,
                                onChanged: (BaseBuild? newValue) {
                                  if (newValue != null && newValue.installPath != null) {
                                    _updateStatus('Cannot create prefix from installed build yet.', isError: true);
                                    return;
                                  }
                                  setState(() { _selectedBuild = newValue; });
                                },
                                hint: const Text('   Select a Proton build'),
                                isExpanded: true,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                items: protonBuilds
                                    .map((build) {
                                       final bool isInstalled = build.installPath != null;
                                       String displayName = isInstalled ? "${build.getDisplayName} (Installed)" : build.getDisplayName;
                                       
                                       // Add source label icons
                                       Widget? leadingIcon;
                                       if (build.name.contains('GE-Proton')) {
                                         leadingIcon = const Icon(Icons.extension, size: 16, color: Colors.green);
                                       } else if (build.name.contains('wine-proton')) {
                                         // No need to modify the display name since we're using getDisplayName now
                                         leadingIcon = const Icon(Icons.wine_bar, size: 16, color: Colors.deepPurple);
                                       }
                                       
                                       return DropdownMenuItem<BaseBuild>(
                                          value: build,
                                          enabled: !isInstalled,
                                          child: Row(
                                            children: [
                                              if (leadingIcon != null) ...[
                                                leadingIcon,
                                                const SizedBox(width: 8),
                                              ],
                                              Expanded(
                                                child: Text(
                                                  displayName,
                                                  style: TextStyle(
                                                    color: isInstalled ? Theme.of(context).disabledColor : null,
                                                  ),
                                                ),
                                              ),
                                            ],
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

            // Prefix Name Card
            Card(
              elevation: 3, margin: const EdgeInsets.only(bottom: 24),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Proton Prefix Name', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                        setState(() { _prefixName = value.trim(); });
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Create Button
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: (_isLoading || _selectedBuild?.type != PrefixType.proton || _prefixName.isEmpty || checkPrefixExists(_prefixName)) 
                  ? null
                  : () => _downloadAndCreatePrefix(PrefixType.proton),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                icon: _isLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary)) : const Icon(Icons.add_circle),
                label: Text(_isLoading ? 'Creating...' : 'Create Proton Prefix', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            // Status and Progress Area
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_status, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _progress > 0 ? _progress : null, backgroundColor: Colors.grey[300]),
                  ],
                ),
              )
            else if (_status != 'Ready' && _status.isNotEmpty) // Show status even if not loading, unless it's just "Ready"
              Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Text(_status, 
                  style: TextStyle(
                    color: _status.toLowerCase().contains('error') || _status.toLowerCase().contains('failed') 
                        ? Theme.of(context).colorScheme.error 
                        : null
                  )
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _updateSelectedType() {
    // Only update if _prefixTabController is not null
    if (_prefixTabController != null) {
      setState(() {
        // Tab 0 is Wine, Tab 1 is Proton
        _selectedPrefixType = _prefixTabController!.index == 0 ? PrefixType.wine : PrefixType.proton;
      });
    }
  }
}