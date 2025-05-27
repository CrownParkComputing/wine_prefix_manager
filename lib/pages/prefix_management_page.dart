import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Import Provider
import '../models/prefix_models.dart'; // Import the prefix models
import '../models/settings.dart'; // Import Settings model
import '../providers/prefix_provider.dart'; // Import the PrefixProvider
import '../providers/settings_provider.dart';
import '../widgets/prefix_creation_form.dart';
import '../services/prefix_creation_service.dart';
import 'package:file_picker/file_picker.dart';
import '../services/log_service.dart';
import '../widgets/prefix_list_tile.dart'; // Import new widget
import '../widgets/prefix_detail_actions.dart'; // Import new widget
import '../widgets/executable_list_tile.dart'; // Import new widget
import '../widgets/rename_prefix_dialog.dart'; // Import rename dialog
// import '../services/wine_component_installer.dart'; // No longer needed directly here
// import 'package:window_manager/window_manager.dart'; // Temporarily disabled
// import '../providers/window_control_provider.dart'; // No longer needed directly here


// Define callback types matching PrefixDetailActions expectations
typedef PrefixActionCallback = void Function(WinePrefix prefix);
typedef PrefixContextActionCallback = void Function(BuildContext context, WinePrefix prefix);
// typedef PrefixSettingsActionCallback = void Function(BuildContext context, WinePrefix prefix, Settings settings); // No longer needed for common components
// Keep original typedef for parent compatibility if needed, or refactor parent too
typedef OnExeAction = Future<void> Function(WinePrefix prefix, ExeEntry exe);
// Added callback type for rename from parent
typedef OnRenamePrefixAction = Future<void> Function(BuildContext context, WinePrefix prefix, String newName);


class PrefixManagementPage extends StatefulWidget {
  const PrefixManagementPage({Key? key}) : super(key: key);

  @override
  State<PrefixManagementPage> createState() => _PrefixManagementPageState();
}

class _PrefixManagementPageState extends State<PrefixManagementPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentIndex = _tabController.index;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create & Manage Prefixes'),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Prefix Settings',
            onPressed: () => _showPrefixSettings(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.6),
          indicatorColor: theme.colorScheme.primary,
          tabs: const [
            Tab(
              icon: Icon(Icons.add_circle_outline),
              text: 'Create Prefix',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCreatePrefixTab(),
        ],
      ),
    );
  }

  Widget _buildCreatePrefixTab() {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: _CreatePrefixTabContent(
            settings: settingsProvider.settings,
            onSuccess: () {
              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Prefix created successfully!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showPrefixSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _PrefixSettingsDialog(),
    );
  }
}

class _CreatePrefixTabContent extends StatefulWidget {
  final Settings settings;
  final VoidCallback? onSuccess;

  const _CreatePrefixTabContent({
    Key? key,
    required this.settings,
    this.onSuccess,
  }) : super(key: key);

  @override
  State<_CreatePrefixTabContent> createState() => _CreatePrefixTabContentState();
}

class _CreatePrefixTabContentState extends State<_CreatePrefixTabContent> {
  PrefixType? _selectedType;

  @override
  Widget build(BuildContext context) {
    return _selectedType == null
        ? _buildPrefixTypeSelection()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with back button
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      setState(() {
                        _selectedType = null;
                      });
                    },
                  ),
                  Text(
                    'Create ${_selectedType == PrefixType.wine ? "Wine" : "Proton"} Prefix',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Show the appropriate creation form
              PrefixCreationForm(
                settings: widget.settings,
                initialPrefixType: _selectedType!,
                onSuccess: widget.onSuccess,
              ),
            ],
          );
  }

  Widget _buildPrefixTypeSelection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Select Prefix Type',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            // Wine Option
            Expanded(
              child: _buildPrefixTypeCard(
                icon: Icons.wine_bar,
                title: 'Wine',
                description: 'Standard Wine prefix for running Windows applications',
                prefixType: PrefixType.wine,
              ),
            ),
            const SizedBox(width: 16),
            // Proton Option
            Expanded(
              child: _buildPrefixTypeCard(
                icon: Icons.games,
                title: 'Proton',
                description: 'Steam Proton prefix optimized for gaming',
                prefixType: PrefixType.proton,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPrefixTypeCard({
    required IconData icon,
    required String title,
    required String description,
    required PrefixType prefixType,
  }) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedType = prefixType;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrefixSettingsDialog extends StatefulWidget {
  @override
  State<_PrefixSettingsDialog> createState() => _PrefixSettingsDialogState();
}

class _PrefixSettingsDialogState extends State<_PrefixSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _prefixDirectoryController;
  late TextEditingController _backupPathController;
  late TextEditingController _wineBuildsApiUrlController;
  late TextEditingController _protonGeApiUrlController;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _prefixDirectoryController = TextEditingController();
    _backupPathController = TextEditingController();
    _wineBuildsApiUrlController = TextEditingController();
    _protonGeApiUrlController = TextEditingController();
    
    _loadSettings();
  }

  @override
  void dispose() {
    _prefixDirectoryController.dispose();
    _backupPathController.dispose();
    _wineBuildsApiUrlController.dispose();
    _protonGeApiUrlController.dispose();
    super.dispose();
  }

  void _loadSettings() {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final settings = settingsProvider.settings;
    
    setState(() {
      _prefixDirectoryController.text = settings.prefixDirectory;
      _backupPathController.text = settings.backupPath ?? '';
      _wineBuildsApiUrlController.text = settings.wineBuildsApiUrl;
      _protonGeApiUrlController.text = settings.protonGeApiUrl;
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      final currentSettings = settingsProvider.settings;
      final logService = Provider.of<LogService>(context, listen: false);

      try {
        final settingsToSave = currentSettings.copyWith(
          prefixDirectory: _prefixDirectoryController.text.trim(),
          backupPath: _backupPathController.text.trim().isEmpty
              ? null
              : _backupPathController.text.trim(),
          wineBuildsApiUrl: _wineBuildsApiUrlController.text.trim(),
          protonGeApiUrl: _protonGeApiUrlController.text.trim(),
        );

        await settingsProvider.updateSettings(settingsToSave);
        logService.log('Prefix settings updated successfully');

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 10),
                  Text('Prefix settings saved successfully'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        logService.log('Failed to save prefix settings: $e', LogLevel.error);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 10),
                  Text('Failed to save settings: $e'),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _selectPrefixDirectory() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Prefix Directory',
        initialDirectory: _prefixDirectoryController.text,
      );

      if (selectedDirectory != null) {
        setState(() {
          _prefixDirectoryController.text = selectedDirectory;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting directory: $e')),
      );
    }
  }

  Future<void> _selectBackupPath() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Backup Directory',
        initialDirectory: _backupPathController.text,
      );

      if (selectedDirectory != null) {
        setState(() {
          _backupPathController.text = selectedDirectory;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting directory: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Prefix Settings'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Directories',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _prefixDirectoryController,
                  decoration: InputDecoration(
                    labelText: 'Prefix Directory',
                    hintText: 'Directory where Wine prefixes are stored',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: _selectPrefixDirectory,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Prefix directory is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _backupPathController,
                  decoration: InputDecoration(
                    labelText: 'Backup Directory (optional)',
                    hintText: 'Directory for storing backups',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: _selectBackupPath,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                Text(
                  'Wine & Proton APIs',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _wineBuildsApiUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Wine Builds API URL',
                    hintText: 'API endpoint for Wine builds',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Wine builds API URL is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _protonGeApiUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Proton GE API URL',
                    hintText: 'API endpoint for Proton GE builds',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Proton GE API URL is required';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveSettings,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
