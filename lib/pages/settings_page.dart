import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart'; // Import file_picker
import 'package:path/path.dart' as path; // Import path package
import '../models/settings.dart';
import '../models/wine_build.dart';
import '../services/cover_art_service.dart'; // Import CoverArtService
import '../theme/theme_provider.dart';

class SettingsPage extends StatefulWidget {
  final Function? onSettingsChanged;

  const SettingsPage({Key? key, this.onSettingsChanged}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _prefixDirController;
  late TextEditingController _igdbClientIdController;
  late TextEditingController _igdbClientSecretController;
  late TextEditingController _gameLibraryPathController;
  Settings? _settings;
  // Controllers for URL settings
  late TextEditingController _dxvkApiUrlController;
  late TextEditingController _vkd3dApiUrlController;
  late TextEditingController _wineBuildsApiUrlController;
  late TextEditingController _protonGeApiUrlController;
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

    _gameLibraryPathController = TextEditingController();
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

    _igdbClientSecretController.dispose();
    _gameLibraryPathController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    final settings = await AppSettings.load();
    String cachePath = 'Error loading path';
    try {
      cachePath = await CoverArtService().getImageCacheDirectoryPath();
    } catch (e) {
      print("Error getting image cache path: $e");
    }

    setState(() {
      _settings = settings;
      _prefixDirController.text = settings.prefixDirectory;
      _igdbClientIdController.text = settings.igdbClientId;
      _igdbClientSecretController.text = settings.igdbClientSecret;
      _selectedCoverSize = settings.coverSize;
      _gameLibraryPathController.text = settings.gameLibraryPath ?? '';
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

      await AppSettings.save(settingsToSave);

      if (widget.onSettingsChanged != null) {
        widget.onSettingsChanged!();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
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
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Select Game Library File Location',
      fileName: '.wine_prefix_manager.json',
    );
    if (outputFile != null) {
      if (!outputFile.toLowerCase().endsWith('.json')) {
        outputFile += '.json';
      }
      // Add null check (restored)
      if (outputFile != null) {
        setState(() {
          _gameLibraryPathController.text = outputFile!; // Use null assertion operator
        });
      }
    }
  }

  // Function to reset API URLs to default - CORRECTLY PLACED IN CLASS SCOPE
  void _resetApiUrls() {
    // Provide all required fields when creating default settings instance
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
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Game Categories',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap( // CORRECTED Wrap syntax
              spacing: 8,
              runSpacing: 8, // Correctly placed parameter
              children: [
                ..._settings!.categories.map((category) {
                  return Chip(
                    label: Text(category),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      final updatedCategories =
                          List<String>.from(_settings!.categories)..remove(category);
                      setState(() {
                        _settings = _settings!.copyWith(categories: updatedCategories); // Use copyWith
                      });
                      _saveSettings();
                    },
                  );
                }).toList(), // Added toList() here
                ActionChip(
                  avatar: const Icon(Icons.add),
                  label: const Text('Add'),
                  onPressed: () => _showAddCategoryDialog(),
                ),
              ],
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
                  // Avoid adding duplicates
                  if (!_settings!.categories.contains(newCategory)) {
                    final updatedCategories =
                        List<String>.from(_settings!.categories)..add(newCategory);
                    setState(() {
                       _settings = _settings!.copyWith(categories: updatedCategories); // Use copyWith
                    });
                    _saveSettings();
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
      // appBar removed previously
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // Theme selector Card... (content omitted for brevity)
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

                    // Game Library Card... (content omitted for brevity)
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

                    // Directories & Files Card... (content omitted for brevity)
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
                           ],
                         ),
                       ),
                     ),

                    // Image Cache Path Display Card... (content omitted for brevity)
                     Card(
                       margin: const EdgeInsets.only(bottom: 16),
                       child: ListTile(
                         leading: const Icon(Icons.image),
                         title: const Text('Image Cache Location'),
                         subtitle: Text(_imageCachePath),
                       ),
                     ),

                    // IGDB API Settings Card... (content omitted for brevity)
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
                                 prefixIcon: Icon(Icons.vpn_key),
                               ),
                             ),
                             const SizedBox(height: 8),
                             TextFormField(
                               controller: _igdbClientSecretController,
                               decoration: const InputDecoration(
                                 labelText: 'IGDB Client Secret',
                                 prefixIcon: Icon(Icons.security),
                               ),
                               obscureText: true,
                             ),
                           ],
                         ),
                       ),
                     ),

                    // API/Service URLs Card
                    Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'API & Service URLs',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _dxvkApiUrlController,
                              decoration: const InputDecoration(labelText: 'DXVK API URL', hintText: 'https://api.github.com/repos/doitsujin/dxvk/releases/latest'),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _vkd3dApiUrlController,
                              decoration: const InputDecoration(labelText: 'VKD3D-Proton API URL', hintText: 'https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest'),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _wineBuildsApiUrlController,
                              decoration: const InputDecoration(labelText: 'Wine Builds API URL', hintText: 'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.4'),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _protonGeApiUrlController,
                              decoration: const InputDecoration(labelText: 'Proton-GE API URL', hintText: 'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases'),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _twitchOAuthUrlController,
                              decoration: const InputDecoration(labelText: 'Twitch OAuth URL', hintText: 'https://id.twitch.tv/oauth2/token'),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _igdbApiBaseUrlController,
                              decoration: const InputDecoration(labelText: 'IGDB API Base URL', hintText: 'https://api.igdb.com/v4'),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _igdbImageBaseUrlController,
                              decoration: const InputDecoration(labelText: 'IGDB Image Base URL', hintText: 'https://images.igdb.com/igdb/image/upload'),
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                onPressed: _resetApiUrls, // This call should now work
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reset URLs to Default'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                  foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    _buildCategoryManagement(),

                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save),
                      label: const Text('Save Settings'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
