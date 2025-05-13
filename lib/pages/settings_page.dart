import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart'; // Import file_picker
import '../models/settings.dart';
import '../services/cover_art_service.dart'; // Import CoverArtService
import '../services/log_service.dart'; // Import LogService
import '../theme/theme_provider.dart';
import '../providers/settings_provider.dart';

class SettingsPage extends StatefulWidget {
  final Function? onSettingsChanged;

  const SettingsPage({Key? key, this.onSettingsChanged}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _prefixDirController;
  late TextEditingController _igdbClientIdController;
  late TextEditingController _igdbClientSecretController;
  late TextEditingController _gameLibraryPathController;
  late TextEditingController _backupPathController; // Add a controller for the backup path
  Settings? _settings;
  // Controllers for URL settings
  late TextEditingController _dxvkApiUrlController;
  late TextEditingController _vkd3dApiUrlController;
  late TextEditingController _wineBuildsApiUrlController;
  late TextEditingController _protonGeApiUrlController;
  
  // Tab controller for the settings tabs
  late TabController _tabController;
  late TextEditingController _twitchOAuthUrlController;
  late TextEditingController _igdbApiBaseUrlController;
  late TextEditingController _igdbImageBaseUrlController;

  bool _isLoading = true;
  CoverSize _selectedCoverSize = CoverSize.medium;
  String _imageCachePath = 'Loading...';

  @override
  void initState() {
    super.initState();
    _prefixDirController = TextEditingController();
    _igdbClientIdController = TextEditingController();
    _igdbClientSecretController = TextEditingController();
    _dxvkApiUrlController = TextEditingController();
    _vkd3dApiUrlController = TextEditingController();
    _wineBuildsApiUrlController = TextEditingController();
    _protonGeApiUrlController = TextEditingController();
    _twitchOAuthUrlController = TextEditingController();
    _igdbApiBaseUrlController = TextEditingController();
    _igdbImageBaseUrlController = TextEditingController();
    _backupPathController = TextEditingController(); // Initialize the backup path controller
    _gameLibraryPathController = TextEditingController();
    
    // Initialize tab controller with 4 tabs
    _tabController = TabController(length: 4, vsync: this);
    
    _loadSettings();
  }

  @override
  void dispose() {
    _prefixDirController.dispose();
    _igdbClientIdController.dispose();
    _dxvkApiUrlController.dispose();
    _vkd3dApiUrlController.dispose();
    _wineBuildsApiUrlController.dispose();
    _protonGeApiUrlController.dispose();
    _twitchOAuthUrlController.dispose();
    _igdbApiBaseUrlController.dispose();
    _igdbImageBaseUrlController.dispose();
    _backupPathController.dispose(); // Dispose the backup path controller
    _igdbClientSecretController.dispose();
    _gameLibraryPathController.dispose();
    _tabController.dispose(); // Dispose tab controller
    super.dispose();
  }

  Future<void> _loadSettings() async {
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

    setState(() {
      _settings = settings;
      _prefixDirController.text = settings.prefixDirectory;
      _igdbClientIdController.text = settings.igdbClientId;
      _igdbClientSecretController.text = settings.igdbClientSecret;
      _selectedCoverSize = settings.coverSize;
      _gameLibraryPathController.text = settings.gameLibraryPath ?? '';
      _backupPathController.text = settings.backupPath ?? ''; // Add backup path to the initialization
      _imageCachePath = cachePath;
      _dxvkApiUrlController.text = settings.dxvkApiUrl;
      _vkd3dApiUrlController.text = settings.vkd3dApiUrl;
      _wineBuildsApiUrlController.text = settings.wineBuildsApiUrl;
      _protonGeApiUrlController.text = settings.protonGeApiUrl;
      _twitchOAuthUrlController.text = settings.twitchOAuthUrl;
      _igdbApiBaseUrlController.text = settings.igdbApiBaseUrl;
      _igdbImageBaseUrlController.text = settings.igdbImageBaseUrl;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      // Show loading indicator
      setState(() {
        _isLoading = true;
      });
      
      // Provide all required fields, even if dummy values are sufficient for defaults here
      final defaultSettings = Settings(
        prefixDirectory: '', igdbClientId: '', igdbClientSecret: '', categories: [],
        // Provide required URL fields (using their actual defaults from Settings constructor)
        dxvkApiUrl: 'https://api.github.com/repos/doitsujin/dxvk/releases/latest',
        vkd3dApiUrl: 'https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest',
        wineBuildsApiUrl: 'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.4',
        protonGeApiUrl: 'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases',
        twitchOAuthUrl: 'https://id.twitch.tv/oauth2/token',
        igdbApiBaseUrl: 'https://api.igdb.com/v4',
        igdbImageBaseUrl: 'https://images.igdb.com/igdb/image/upload',
      );

      final settingsToSave = Settings(
        prefixDirectory: _prefixDirController.text.trim(),
        igdbClientId: _igdbClientIdController.text.trim(),
        igdbClientSecret: _igdbClientSecretController.text.trim(),
        igdbAccessToken: _settings?.igdbAccessToken,
        igdbTokenExpiry: _settings?.igdbTokenExpiry,
        coverSize: _selectedCoverSize,
        categories: _settings!.categories,
        gameLibraryPath: _gameLibraryPathController.text.trim().isEmpty
            ? null
            : _gameLibraryPathController.text.trim(),
        backupPath: _backupPathController.text.trim().isEmpty
            ? null
            : _backupPathController.text.trim(), // Include the backup path
        dxvkApiUrl: _dxvkApiUrlController.text.trim().isEmpty
            ? defaultSettings.dxvkApiUrl
            : _dxvkApiUrlController.text.trim(),
        vkd3dApiUrl: _vkd3dApiUrlController.text.trim().isEmpty
            ? defaultSettings.vkd3dApiUrl
            : _vkd3dApiUrlController.text.trim(),
        wineBuildsApiUrl: _wineBuildsApiUrlController.text.trim().isEmpty
            ? defaultSettings.wineBuildsApiUrl
            : _wineBuildsApiUrlController.text.trim(),
        protonGeApiUrl: _protonGeApiUrlController.text.trim().isEmpty
            ? defaultSettings.protonGeApiUrl
            : _protonGeApiUrlController.text.trim(),
        twitchOAuthUrl: _twitchOAuthUrlController.text.trim().isEmpty
            ? defaultSettings.twitchOAuthUrl
            : _twitchOAuthUrlController.text.trim(),
        igdbApiBaseUrl: _igdbApiBaseUrlController.text.trim().isEmpty
            ? defaultSettings.igdbApiBaseUrl
            : _igdbApiBaseUrlController.text.trim(),
        igdbImageBaseUrl: _igdbImageBaseUrlController.text.trim().isEmpty
            ? defaultSettings.igdbImageBaseUrl
            : _igdbImageBaseUrlController.text.trim(),
      );

      try {
        // Use the SettingsProvider to update settings
        if (mounted) {
          await Provider.of<SettingsProvider>(context, listen: false).updateSettings(settingsToSave);
          
          // Log the settings change
          final logService = Provider.of<LogService>(context, listen: false);
          logService.log('Settings updated successfully');
        }

        if (widget.onSettingsChanged != null) {
          widget.onSettingsChanged!();
        }

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 10),
                  const Text('Settings saved successfully'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        // Show error message if saving fails
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error, color: Colors.white),
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
    if (selectedDirectory != null) {
      setState(() {
        _prefixDirController.text = selectedDirectory;
      });
    }
  }

  Future<void> _pickGameLibraryPath() async {
    final outputFile = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Game Library Path',
      initialDirectory: _gameLibraryPathController.text.isNotEmpty
          ? _gameLibraryPathController.text
          : _settings?.prefixDirectory,
    );

    if (outputFile != null) {
      setState(() {
        _gameLibraryPathController.text = outputFile;
      });
    }
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

  void _resetApiUrls() {
    final defaultSettings = Settings(
      prefixDirectory: '', igdbClientId: '', igdbClientSecret: '', categories: [],
      dxvkApiUrl: 'https://api.github.com/repos/doitsujin/dxvk/releases/latest',
      vkd3dApiUrl: 'https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest',
      wineBuildsApiUrl: 'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.4',
      protonGeApiUrl: 'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases',
      twitchOAuthUrl: 'https://id.twitch.tv/oauth2/token',
      igdbApiBaseUrl: 'https://api.igdb.com/v4',
      igdbImageBaseUrl: 'https://images.igdb.com/igdb/image/upload',
    );
    setState(() {
      _dxvkApiUrlController.text = defaultSettings.dxvkApiUrl;
      _vkd3dApiUrlController.text = defaultSettings.vkd3dApiUrl;
      _wineBuildsApiUrlController.text = defaultSettings.wineBuildsApiUrl;
      _protonGeApiUrlController.text = defaultSettings.protonGeApiUrl;
      _twitchOAuthUrlController.text = defaultSettings.twitchOAuthUrl;
      _igdbApiBaseUrlController.text = defaultSettings.igdbApiBaseUrl;
      _igdbImageBaseUrlController.text = defaultSettings.igdbImageBaseUrl;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API URLs reset to defaults. Save settings to apply.')),
    );
  }

  Widget _buildCategoryManagement() {
    if (_settings == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Game Categories',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Category'),
                  onPressed: () => _showAddCategoryDialog(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Organize your games with custom categories:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _settings!.categories.isEmpty
                ? [
                    const Chip(
                      label: Text('No categories yet'),
                      backgroundColor: Colors.grey,
                    ),
                  ]
                : _settings!.categories.map((category) {
                    return Chip(
                      label: Text(category),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () {
                        final updatedCategories =
                            List<String>.from(_settings!.categories)..remove(category);
                        setState(() {
                          _settings = _settings!.copyWith(categories: updatedCategories);
                        });
                        _saveSettings();
                      },
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCategoryDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Category'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Category Name',
              hintText: 'e.g., Favorites, Completed, Playing',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  final newCategory = controller.text.trim();
                  if (!_settings!.categories.contains(newCategory)) {
                    final updatedCategories =
                        List<String>.from(_settings!.categories)..add(newCategory);
                    setState(() {
                      _settings = _settings!.copyWith(categories: updatedCategories);
                    });
                    _saveSettings();
                    
                    // Add logging for category creation
                    final logService = Provider.of<LogService>(context, listen: false);
                    logService.log('New category created: $newCategory');
                  }
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

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
                Tab(icon: Icon(Icons.folder), text: 'Directories'),
                Tab(icon: Icon(Icons.category), text: 'Categories'),
                Tab(icon: Icon(Icons.api), text: 'API Settings'),
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
                  // GENERAL TAB
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // Appearance Card
                        Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Appearance',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SwitchListTile(
                                  title: const Text('Dark Mode'),
                                  subtitle: const Text('Enable dark theme'),
                                  secondary: Icon(
                                    themeProvider.isDarkMode
                                        ? Icons.dark_mode
                                        : Icons.light_mode,
                                    color: themeProvider.isDarkMode
                                        ? Colors.amber
                                        : Colors.deepPurple,
                                  ),
                                  value: themeProvider.isDarkMode,
                                  onChanged: (_) {
                                    themeProvider.toggleTheme();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        // Game Library Card
                        Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Game Library',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Text('Cover Size'),
                                const SizedBox(height: 8),
                                SegmentedButton<CoverSize>(
                                  segments: const [
                                    ButtonSegment<CoverSize>(
                                      value: CoverSize.small,
                                      label: Text('Small'),
                                      icon: Icon(Icons.photo_size_select_small),
                                    ),
                                    ButtonSegment<CoverSize>(
                                      value: CoverSize.medium,
                                      label: Text('Medium'),
                                      icon: Icon(Icons.photo_size_select_actual),
                                    ),
                                    ButtonSegment<CoverSize>(
                                      value: CoverSize.large,
                                      label: Text('Large'),
                                      icon: Icon(Icons.photo_size_select_large),
                                    ),
                                  ],
                                  selected: <CoverSize>{_selectedCoverSize},
                                  onSelectionChanged: (Set<CoverSize> newSelection) {
                                    setState(() {
                                      _selectedCoverSize = newSelection.first;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        // Save button
                        ElevatedButton(
                          onPressed: _saveSettings,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          child: const Text('Save Settings'),
                        ),
                      ],
                    ),
                  ),
                  
                  // DIRECTORIES TAB
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // Directories Card
                        Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Directories & Files',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _prefixDirController,
                                  decoration: InputDecoration(
                                    labelText: 'Prefix Directory',
                                    helperText: 'Main directory where prefixes are stored',
                                    prefixIcon: const Icon(Icons.folder),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.more_horiz),
                                      tooltip: 'Browse',
                                      onPressed: _pickPrefixDirectory,
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter a directory path';
                                    }
                                    return null;
                                  },
                                  readOnly: true,
                                  onTap: _pickPrefixDirectory,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _gameLibraryPathController,
                                  decoration: InputDecoration(
                                    labelText: 'Game Library File Path (Optional)',
                                    helperText: 'Path to save the game library JSON file. Leave blank for default (~/.wine_prefix_manager.json).',
                                    prefixIcon: const Icon(Icons.save_alt),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.more_horiz),
                                      tooltip: 'Browse',
                                      onPressed: _pickGameLibraryPath,
                                    ),
                                  ),
                                  readOnly: true,
                                  onTap: _pickGameLibraryPath,
                                ),
                                const SizedBox(height: 16),
                                _buildBackupFolderSetting(), // Add backup path setting
                              ],
                            ),
                          ),
                        ),
                        
                        // Image Cache Card
                        Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: ListTile(
                            leading: const Icon(Icons.image),
                            title: const Text('Image Cache Location'),
                            subtitle: Text(_imageCachePath),
                          ),
                        ),
                        
                        // Save button
                        ElevatedButton(
                          onPressed: _saveSettings,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          child: const Text('Save Settings'),
                        ),
                      ],
                    ),
                  ),
                  
                  // CATEGORIES TAB
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildCategoryManagement(),
                        
                        // Save button
                        ElevatedButton(
                          onPressed: _saveSettings,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          child: const Text('Save Settings'),
                        ),
                      ],
                    ),
                  ),
                  
                  // API SETTINGS TAB
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // IGDB API Settings Card
                        Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'IGDB API Settings',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _igdbClientIdController,
                                  decoration: const InputDecoration(
                                    labelText: 'IGDB Client ID',
                                    hintText: 'Enter your Twitch/IGDB Client ID',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your IGDB Client ID';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _igdbClientSecretController,
                                  decoration: const InputDecoration(
                                    labelText: 'IGDB Client Secret',
                                    hintText: 'Enter your Twitch/IGDB Client Secret',
                                  ),
                                  obscureText: true,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your IGDB Client Secret';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        // API URLs Card
                        Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'API URLs (Advanced)',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _resetApiUrls,
                                      child: const Text('Reset Defaults'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildUrlTextField(_dxvkApiUrlController, 'DXVK API URL'),
                                _buildUrlTextField(_vkd3dApiUrlController, 'VKD3D-Proton API URL'),
                                _buildUrlTextField(_wineBuildsApiUrlController, 'Wine Builds API URL'),
                                _buildUrlTextField(_protonGeApiUrlController, 'Proton-GE API URL'),
                                _buildUrlTextField(_twitchOAuthUrlController, 'Twitch OAuth URL'),
                                _buildUrlTextField(_igdbApiBaseUrlController, 'IGDB API Base URL'),
                                _buildUrlTextField(_igdbImageBaseUrlController, 'IGDB Image Base URL'),
                              ],
                            ),
                          ),
                        ),
                        
                        // Save button
                        ElevatedButton(
                          onPressed: _saveSettings,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          child: const Text('Save Settings'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildUrlTextField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Leave blank for default',
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildBackupFolderSetting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Backup Folder', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _backupPathController,
                readOnly: true,
                decoration: const InputDecoration(
                  hintText: 'Path for game backups',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Browse'),
              onPressed: _pickBackupPath,
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'This is where game backups will be stored.',
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}
