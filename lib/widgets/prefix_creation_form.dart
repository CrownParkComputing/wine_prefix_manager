import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/wine_build.dart';
import '../models/build_models.dart'; // Import for ProtonBuild
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
    super.key, 
    required this.settings,
    this.initialPrefixType, // Optional parameter
    this.onSuccess, // <<<< Added this
  });

  @override
  State<PrefixCreationForm> createState() => _PrefixCreationFormState();
}

class _PrefixCreationFormState extends State<PrefixCreationForm> with TickerProviderStateMixin {
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
          _status = 'Found [200b${builds.length}[200b} builds';
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
    if (_selectedBuild == null) {
      _updateStatus('Please select a build.', isError: true);
      return;
    }
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
      _progress = 0.0;
    });
    _logService.log('Starting prefix creation for "$_prefixName"...');
    final String architectureToPass = (prefixType == PrefixType.proton) ? 'win64' : _selectedArchitecture;
    try {
      final newPrefix = await _prefixCreationService.downloadAndCreatePrefix(
        selectedBuild: _selectedBuild,
        prefixName: _prefixName,
        settings: widget.settings!,
        prefixType: prefixType,
        architecture: architectureToPass,
        onStatusUpdate: (status) {
          if (mounted) setState(() { _status = status; });
        },
        onProgressUpdate: (progress) {
          if (mounted) setState(() { _progress = progress; });
        },
      );
      if (newPrefix != null && mounted) {
        prefixProvider.addCreatedPrefix(newPrefix);
        _updateStatus('Prefix "$_prefixName" created successfully!');
        setState(() {
          _prefixNameController.clear();
          _prefixName = '';
          _selectedBuild = null;
        });
        widget.onSuccess?.call();
      } else if (mounted) {
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
  // Private fields for state
  List<BaseBuild> _builds = [];
  BaseBuild? _selectedBuild;
  bool _isLoading = false;
  String _selectedProtonType = 'GE-Proton';
  final List<String> _protonTypes = ['GE-Proton', 'Kronek Proton', 'CachyOS Proton'];
  String _prefixName = '';
  String _status = 'Ready';
  double _progress = 0.0;
  String _selectedArchitecture = 'win64';
  final TextEditingController _prefixNameController = TextEditingController();
  final BuildService _buildService = BuildService();
  final PrefixCreationService _prefixCreationService = PrefixCreationService();
  final LogService _logService = LogService();
  // All methods are now defined only once at the class level.
  // Refresh Wine builds for dropdown
  void _refreshWineBuilds() {
    _fetchBuilds();
  }

  // Create Wine prefix from selected build
  void _createWinePrefix() {
    _downloadAndCreatePrefix(PrefixType.wine);
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
        .where((build) => build.architecture == _selectedArchitecture || build.architecture == null)
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                      ),
                      initialValue: _selectedArchitecture,
                      items: const [
                        DropdownMenuItem(value: 'win64', child: Text('64-bit (win64)')),
                        DropdownMenuItem(value: 'win32', child: Text('32-bit (win32)')),
                      ],
                      onChanged: (String? newValue) {
                        if (newValue != null && newValue != _selectedArchitecture) {
                          setState(() {
                            _selectedArchitecture = newValue;
                            if (_selectedBuild != null && _selectedBuild!.architecture != null && _selectedBuild!.architecture != _selectedArchitecture) {
                              _selectedBuild = null;
                            }
                          });
                        }
                      },
                    ),
                  ],
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
                          onPressed: _isLoading ? null : _refreshWineBuilds,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<BaseBuild>(
                        value: _selectedBuild?.type == PrefixType.wine ? _selectedBuild : null,
                        onChanged: (BaseBuild? newValue) {
                          setState(() { _selectedBuild = newValue; });
                        },
                        hint: const Text('   Select a Wine build'),
                        isExpanded: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        items: filteredWineBuilds
                            .map((build) {
                               final bool isInstalled = build.installPath != null;
                               String displayName = isInstalled ? "${build.getDisplayName} (Installed)" : build.getDisplayName;
                               return DropdownMenuItem<BaseBuild>(
                                  value: build,
                                  enabled: !isInstalled,
                                  child: Text(displayName),
                                );
                            })
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Prefix Name Card (context-aware label)
            Card(
              elevation: 3, margin: const EdgeInsets.only(bottom: 24),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedProtonType == 'Steam Proton'
                          ? 'Proton Prefix Name'
                          : 'Wine Prefix Name',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
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
                  : () => _createWinePrefix(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                icon: _isLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary)) : const Icon(Icons.add),
                label: Text(_isLoading ? 'Creating...' : 'Create Prefix', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            if (_status != 'Ready' && _status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Text(_status, style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProtonPrefixTab(bool Function(String) checkPrefixExists) {
    // Proton type selection logic
    List<BaseBuild> filteredBuilds = [];
    if (_selectedProtonType == 'GE-Proton') {
      filteredBuilds = _builds.where((build) => build.type == PrefixType.proton && build.name.contains('GE-Proton')).toList();
    } else if (_selectedProtonType == 'Kronek Proton') {
      filteredBuilds = _builds.where((build) => build.type == PrefixType.proton && (build.name.toLowerCase().contains('kronek') || build.name.toLowerCase().contains('wine-proton'))).toList();
    } else if (_selectedProtonType == 'CachyOS Proton') {
      filteredBuilds = _builds.where((build) => build.type == PrefixType.proton && (build.displayName?.contains('CachyOS Proton') == true || build.name.contains('cachyos'))).toList();
    }
    
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Proton type selection
            Card(
              elevation: 3, margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Text('Proton Type:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    DropdownButton<String>(
                      value: _selectedProtonType,
                      onChanged: (String? newType) {
                        if (newType != null) {
                          setState(() {
                            _selectedProtonType = newType;
                            _selectedBuild = null;
                          });
                        }
                      },
                      items: _protonTypes.map((type) => DropdownMenuItem<String>(
                        value: type,
                        child: Text(type),
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ),
            // Unified Prefix Name Card (Always visible)
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
            // Build selection for GE/Kronek/CachyOS Proton
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
                          Text('Select $_selectedProtonType Build', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _isLoading ? null : _fetchBuilds,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<BaseBuild>(
                          value: _selectedBuild?.type == PrefixType.proton ? _selectedBuild : null,
                          onChanged: (BaseBuild? newValue) {
                            setState(() { _selectedBuild = newValue; });
                          },
                          hint: Text('   Select a $_selectedProtonType build'),
                          isExpanded: true,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          items: filteredBuilds
                              .map((build) {
                                 final bool isInstalled = build.installPath != null;
                                 String displayName = isInstalled ? "${build.getDisplayName} (Installed)" : build.getDisplayName;
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
                      const SizedBox(height: 16),
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
                          label: Text(_isLoading ? 'Creating...' : 'Create $_selectedProtonType Prefix', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
            ),

            // Unified Status and Progress Area (shown for all Proton types)
            if (_status != 'Ready' && _status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Status',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_isLoading && _progress > 0) 
                              Text(
                                '${(_progress * 100).toStringAsFixed(1)}%',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_isLoading)
                          LinearProgressIndicator(
                            value: _progress > 0 ? _progress : null,
                            backgroundColor: Colors.grey[300],
                          ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(color: Theme.of(context).colorScheme.outline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              _status,
                              style: TextStyle(
                                color: _status.toLowerCase().contains('error') || _status.toLowerCase().contains('failed') 
                                    ? Theme.of(context).colorScheme.error 
                                    : Theme.of(context).textTheme.bodyMedium?.color,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
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
