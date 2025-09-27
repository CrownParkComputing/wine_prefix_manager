import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart'; // Import file_picker
import 'dart:io'; // Added for Platform.environment
import 'package:path/path.dart' as path; // Added for path.join
import '../models/settings.dart';
import '../services/cover_art_service.dart'; // Import CoverArtService
import '../services/log_service.dart'; // Import LogService
import '../services/power_management_service.dart'; // Import PowerManagementService
import '../theme/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/json_viewer_page.dart'; // Import the JSON viewer

class SettingsPage extends StatefulWidget {
  final Function? onSettingsChanged;

  const SettingsPage({Key? key, this.onSettingsChanged}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _prefixDirController;
  late TextEditingController _gameLibraryPathController;
  late TextEditingController _backupPathController; // Add a controller for the backup path
  Settings? _settings;
  // Controllers for URL settings
  late TabController _tabController;
  late TextEditingController _twitchOAuthUrlController;
  late TextEditingController _igdbApiBaseUrlController;
  late TextEditingController _igdbImageBaseUrlController;

  bool _isLoading = true;
  CoverSize _selectedCoverSize = CoverSize.medium;
  String _imageCachePath = 'Loading...';

  // Create a dummy settings instance to access default URL values
  final _defaultSettingsInstance = Settings(
    prefixDirectory: '', // Dummy value, not used for defaults here
    categories: [], // Dummy value
    igdbImageBaseUrl: '' // Dummy value, actual default taken from constructor if needed elsewhere
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Initialize controllers with empty strings
    _prefixDirController = TextEditingController();
    _gameLibraryPathController = TextEditingController();
    _backupPathController = TextEditingController();
    // URL settings controllers
    _twitchOAuthUrlController = TextEditingController();
    _igdbApiBaseUrlController = TextEditingController();
    _igdbImageBaseUrlController = TextEditingController();
    
    // Load settings
    _loadSettings();
  }

  @override
  void dispose() {
    // Dispose controllers
    _prefixDirController.dispose();
    _gameLibraryPathController.dispose();
    _backupPathController.dispose();
    // URL settings controllers
    _twitchOAuthUrlController.dispose();
    _igdbApiBaseUrlController.dispose();
    _igdbImageBaseUrlController.dispose();
    // Tab controller
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final settings = settingsProvider.settings;
    String cachePath = 'Error loading path';
    try {
      cachePath = await CoverArtService().getImageCacheDirectoryPath();
    } catch (e) {
      // Error getting image cache path
    }

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _prefixDirController.text = settings.prefixDirectory;
      _selectedCoverSize = settings.coverSize;
      _gameLibraryPathController.text = settings.gameLibraryPath ?? '';
      _backupPathController.text = settings.backupPath ?? ''; // Add backup path to the initialization
      _imageCachePath = cachePath;
      _twitchOAuthUrlController.text = settings.twitchOAuthUrl;
      _igdbApiBaseUrlController.text = settings.igdbApiBaseUrl;
      _igdbImageBaseUrlController.text = settings.igdbImageBaseUrl;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      if (!mounted) return;
      // Show loading indicator
      setState(() {
        _isLoading = true;
      });
      
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      final currentSettings = settingsProvider.settings; // Get current settings to preserve others
      final logService = Provider.of<LogService>(context, listen: false);

      // Create new settings object, only updating fields managed by this page
      final settingsToSave = currentSettings.copyWith(
        prefixDirectory: _prefixDirController.text.trim(),
        coverSize: _selectedCoverSize,
        gameLibraryPath: _gameLibraryPathController.text.trim().isEmpty
            ? null
            : _gameLibraryPathController.text.trim(),
        backupPath: _backupPathController.text.trim().isEmpty
            ? null
            : _backupPathController.text.trim(),
        twitchOAuthUrl: _twitchOAuthUrlController.text.trim().isEmpty
            ? _defaultSettingsInstance.twitchOAuthUrl // Use default from dummy instance
            : _twitchOAuthUrlController.text.trim(),
        igdbApiBaseUrl: _igdbApiBaseUrlController.text.trim().isEmpty
            ? _defaultSettingsInstance.igdbApiBaseUrl // Use default from dummy instance
            : _igdbApiBaseUrlController.text.trim(),
        igdbImageBaseUrl: _igdbImageBaseUrlController.text.trim().isEmpty
            ? _defaultSettingsInstance.igdbImageBaseUrl // Use default from dummy instance
            : _igdbImageBaseUrlController.text.trim(),
      );

      try {
        await settingsProvider.updateSettings(settingsToSave);
        logService.log('Settings updated successfully');

        if (widget.onSettingsChanged != null) {
          widget.onSettingsChanged!();
        }

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 10),
                  Text('Settings saved successfully'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        logService.log('Failed to save settings: $e', LogLevel.error);
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
        // Hide loading indicator
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _pickPrefixDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Prefix Directory',
    );
    setState(() {
      _prefixDirController.text = selectedDirectory;
    });
    }

  Future<void> _pickGameLibraryPath() async {
    // Corrected to pick a file, not a directory, for the game library path
    String? selectedFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Select Game Library JSON File',
      fileName: '.wine_prefix_manager.json',
      allowedExtensions: ['json'],
      type: FileType.custom,
      initialDirectory: _gameLibraryPathController.text.isNotEmpty
          ? path.dirname(_gameLibraryPathController.text) // Use parent directory if path exists
          : (_settings?.prefixDirectory ?? Platform.environment['HOME']), // Default to prefix or home
    );

    setState(() {
      _gameLibraryPathController.text = selectedFile;
    });
    }

  Future<void> _pickBackupPath() async {
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Backup Folder',
      initialDirectory: _backupPathController.text.isNotEmpty
          ? _backupPathController.text
          : _settings?.prefixDirectory,
    );
    if (directory != null) {
      setState(() {
        _backupPathController.text = directory;
      });
    }
  }

  Widget _buildGeneralSettingsTab() {
    String defaultGameLibPath = 'Loading...';
    try {
      final homeDir = Platform.environment['HOME'];
      if (homeDir != null) {
        defaultGameLibPath = path.join(homeDir, '.wine_prefix_manager.json');
      } else {
        defaultGameLibPath = '.wine_prefix_manager.json (HOME not found)';
      }
    } catch (e) {
        defaultGameLibPath = 'Error getting default path';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('General Paths', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          _buildDirectoryPicker(
            label: 'Prefix Directory',
            controller: _prefixDirController,
            dialogTitle: 'Select Default Prefix Directory',
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Prefix directory cannot be empty';
              }
              return null;
            },
            onPick: _pickPrefixDirectory,
            isFilePicker: false,
          ),
          _buildDirectoryPicker(
            label: 'Game Library Path (Optional)',
            controller: _gameLibraryPathController,
            dialogTitle: 'Select Game Library JSON File',
            onPick: _pickGameLibraryPath,
            helperText: 'Defaults to: $defaultGameLibPath',
            isFilePicker: true, // Specify this is for a file
            trailingWidget: IconButton(
              icon: const Icon(Icons.visibility),
              tooltip: 'View Game Library JSON',
              onPressed: () async {
                final settings = Provider.of<SettingsProvider>(context, listen: false).settings;
                String gameLibPath;

                if (settings.gameLibraryPath != null && settings.gameLibraryPath!.isNotEmpty) {
                  gameLibPath = settings.gameLibraryPath!;
                } else {
                  final homeDir = Platform.environment['HOME'];
                  if (homeDir == null) {
                    if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Error: HOME environment variable not set.')),
                        );
                    }
                    return;
                  }
                  gameLibPath = path.join(homeDir, '.wine_prefix_manager.json');
                }
                
                // Ensure the directory for the game library path exists if it's custom and path is set
                // This logic is more for safety, as the viewer itself checks for file existence.
                if (settings.gameLibraryPath != null && settings.gameLibraryPath!.isNotEmpty) {
                  try {
                    final dir = Directory(path.dirname(settings.gameLibraryPath!));
                    if (!await dir.exists()) {
                      // We generally shouldn't create the directory here if the file doesn't exist.
                      // The PrefixStorageService handles directory creation when saving.
                      // The viewer will report if the file isn't found.
                    }
                  } catch (e) {
                    print('Error accessing directory for game library path: $e');
                  }
                }

                if (mounted) {
                    showDialog(
                        context: context,
                        builder: (_) => JsonViewerPage(filePath: gameLibPath),
                    );
                }
              },
            ),
          ),
           _buildDirectoryPicker(
            label: 'Backup Path (Optional)',
            controller: _backupPathController,
            dialogTitle: 'Select Backup Path',
            onPick: _pickBackupPath,
            isFilePicker: false,
          ),
          const SizedBox(height: 20),
          const Text('Cover Art Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          ListTile(
            title: const Text('Preferred Cover Size'),
            trailing: DropdownButton<CoverSize>(
              value: _selectedCoverSize,
              items: CoverSize.values.map((CoverSize size) {
                return DropdownMenuItem<CoverSize>(
                  value: size,
                  child: Text(size.name), // Or a more descriptive name
                );
              }).toList(),
              onChanged: (CoverSize? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedCoverSize = newValue;
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text('Power Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          Builder(
            builder: (context) {
              final powerService = Provider.of<PowerManagementService>(context, listen: false);
              return Column(
                children: [
                  ListTile(
                    title: const Text('Sleep Inhibit Status'),
                    subtitle: Text(powerService.isInhibited 
                        ? 'Currently preventing system sleep' 
                        : 'System sleep is allowed'),
                    trailing: Icon(
                      powerService.isInhibited ? Icons.block : Icons.check_circle,
                      color: powerService.isInhibited ? Colors.orange : Colors.green,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: powerService.isInhibited ? null : () async {
                          final success = await powerService.inhibitSleep(
                            reason: 'Manual sleep inhibit from settings'
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(success 
                                    ? 'Sleep inhibited successfully' 
                                    : 'Failed to inhibit sleep'),
                                backgroundColor: success ? Colors.green : Colors.red,
                              ),
                            );
                          }
                          setState(() {}); // Refresh the UI
                        },
                        icon: const Icon(Icons.block),
                        label: const Text('Inhibit Sleep'),
                      ),
                      ElevatedButton.icon(
                        onPressed: !powerService.isInhibited ? null : () async {
                          await powerService.allowSleep();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Sleep allowed'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                          setState(() {}); // Refresh the UI
                        },
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Allow Sleep'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Automatic sleep inhibit is enabled during game sessions',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const Text('Theme Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return ListTile(
                title: const Text('Dark Mode'),
                trailing: Switch(
                  value: themeProvider.isDarkMode,
                  onChanged: (value) {
                    themeProvider.toggleTheme(); // Removed value argument
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildApiSettingsTab() {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('IGDB API Settings (for Game Information)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Divider(),
          Text('IGDB Client ID and Secret are now configured globally in the application.'),
          SizedBox(height: 20),
          Text('All IGDB API URLs are now configured globally for optimal performance.'),
          SizedBox(height: 16),
          Text('No additional configuration is required for IGDB integration.', 
                     style: TextStyle(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildUrlSettingField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
        ),
        validator: (value) {
          if (value != null && value.trim().isNotEmpty) {
            // Corrected Uri.isAbsolute check
            if (!(Uri.tryParse(value.trim())?.isAbsolute == true)) {
              return 'Please enter a valid URL';
            }
          }
          return null; // Allow empty if it's optional, or add specific empty check if required
        },
      ),
    );
  }

  Widget _buildDirectoryPicker({
    required String label,
    required TextEditingController controller,
    required String dialogTitle,
    String? Function(String?)? validator,
    required Future<void> Function() onPick,
    String? helperText,
    Widget? trailingWidget,
    bool isFilePicker = false, // Added to distinguish file from directory
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                helperText: helperText,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              validator: validator,
              readOnly: true, 
              onTap: onPick, 
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(isFilePicker ? Icons.attach_file : Icons.folder_open), // Change icon based on type
            tooltip: isFilePicker ? 'Select File' : 'Browse Directory',
            onPressed: onPick,
          ),
          if (trailingWidget != null) ...[
            const SizedBox(width: 4),
            trailingWidget,
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          // Help button with tooltip
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Setting Information',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Settings are organized into tabs for easier navigation'),
                  duration: Duration(seconds: 3),
                )
              );
            },
          ),
        ],
        bottom: _isLoading 
          ? null 
          : TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorWeight: 3,
              indicatorColor: Theme.of(context).colorScheme.primary,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(icon: Icon(Icons.settings), text: 'General'),
                Tab(icon: Icon(Icons.api), text: 'APIs & URLs'),
              ],
            ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGeneralSettingsTab(),
                  _buildApiSettingsTab(),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _saveSettings,
        icon: _isLoading ? const SizedBox(width:20, height:20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
        label: const Text('Save Settings'),
      ),
    );
  }
}
