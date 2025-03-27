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
  late TextEditingController _gameLibraryPathController; // Controller for game library path
  Settings? _settings;
  bool _isLoading = true;
  CoverSize _selectedCoverSize = CoverSize.medium;
  String _imageCachePath = 'Loading...'; // State variable for cache path

  @override
  void initState() {
    super.initState();
    _prefixDirController = TextEditingController();
    _igdbClientIdController = TextEditingController();
    _igdbClientSecretController = TextEditingController();
    _gameLibraryPathController = TextEditingController(); // Initialize controller
    _loadSettings();
  }

  @override
  void dispose() {
    _prefixDirController.dispose();
    _igdbClientIdController.dispose();
    _igdbClientSecretController.dispose();
    _gameLibraryPathController.dispose(); // Dispose controller
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    final settings = await AppSettings.load();
    // Fetch cache path
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
      _gameLibraryPathController.text = settings.gameLibraryPath ?? ''; // Set text, default to empty
      _imageCachePath = cachePath; // Set the path state
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      final settings = Settings(
        prefixDirectory: _prefixDirController.text.trim(),
        igdbClientId: _igdbClientIdController.text.trim(),
        igdbClientSecret: _igdbClientSecretController.text.trim(),
        igdbAccessToken: _settings?.igdbAccessToken,
        igdbTokenExpiry: _settings?.igdbTokenExpiry,
        coverSize: _selectedCoverSize, // Save selected cover size
        categories: _settings!.categories,
        gameLibraryPath: _gameLibraryPathController.text.trim().isEmpty
            ? null // Store null if empty to use default
            : _gameLibraryPathController.text.trim(),
      );

      await AppSettings.save(settings);

      if (widget.onSettingsChanged != null) {
        widget.onSettingsChanged!();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  // Function to pick directory for prefix directory
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

  // Function to pick file path for game library
  Future<void> _pickGameLibraryPath() async {
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Select Game Library File Location',
      fileName: '.wine_prefix_manager.json', // Default filename
      // allowedExtensions: ['json'], // Optional: Restrict to json
      // lockParentWindow: true, // Optional: Modal behavior
    );

    if (outputFile != null) {
      // Ensure the file has a .json extension if user didn't provide one
      if (!outputFile.toLowerCase().endsWith('.json')) {
        outputFile += '.json';
      }
      setState(() {
        _gameLibraryPathController.text = outputFile!; // Use null assertion here
      });
    }
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._settings!.categories.map((category) {
                  return Chip(
                    label: Text(category),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      final updatedCategories =
                          List<String>.from(_settings!.categories)..remove(category);

                      setState(() {
                        // Create a new Settings object with updated categories
                        _settings = Settings(
                          prefixDirectory: _settings!.prefixDirectory,
                          igdbClientId: _settings!.igdbClientId,
                          igdbClientSecret: _settings!.igdbClientSecret,
                          igdbAccessToken: _settings!.igdbAccessToken,
                          igdbTokenExpiry: _settings!.igdbTokenExpiry,
                          coverSize: _settings!.coverSize,
                          categories: updatedCategories, // Use updated list
                          gameLibraryPath: _settings!.gameLibraryPath, // Keep existing path
                        );
                      });
                      _saveSettings(); // Save after state update
                    },
                  );
                }),
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
                  final updatedCategories =
                      List<String>.from(_settings!.categories)..add(newCategory);

                  setState(() {
                    // Create a new Settings object with updated categories
                    _settings = Settings(
                      prefixDirectory: _settings!.prefixDirectory,
                      igdbClientId: _settings!.igdbClientId,
                      igdbClientSecret: _settings!.igdbClientSecret,
                      igdbAccessToken: _settings!.igdbAccessToken,
                      igdbTokenExpiry: _settings!.igdbTokenExpiry,
                      coverSize: _settings!.coverSize,
                      categories: updatedCategories, // Use updated list
                      gameLibraryPath: _settings!.gameLibraryPath, // Keep existing path
                    );
                  });
                  _saveSettings(); // Save after state update
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
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // Theme selector
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

                    // Game Library
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

                    // Directories
                    Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Directories & Files', // Updated title
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Prefix Directory Field
                            TextFormField(
                              controller: _prefixDirController,
                              decoration: InputDecoration(
                                labelText: 'Prefix Directory',
                                helperText:
                                    'Main directory where prefixes are stored',
                                prefixIcon: const Icon(Icons.folder),
                                suffixIcon: IconButton( // Add browse button
                                  icon: const Icon(Icons.more_horiz),
                                  tooltip: 'Browse',
                                  onPressed: _pickPrefixDirectory,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a directory path';
                                }
                                // Basic validation: check if it looks like a path
                                // More robust validation (e.g., checking existence) could be added
                                return null;
                              },
                              readOnly: true, // Make field read-only, use button to change
                              onTap: _pickPrefixDirectory, // Allow tapping field to browse too
                            ),
                            const SizedBox(height: 16), // Add spacing
                            // Game Library Path Field
                            TextFormField(
                              controller: _gameLibraryPathController,
                              decoration: InputDecoration(
                                labelText: 'Game Library File Path (Optional)',
                                helperText:
                                    'Path to save the game library JSON file (e.g., /path/to/your/library.json). Leave blank to use default (~/.wine_prefix_manager.json).',
                                prefixIcon: const Icon(Icons.save_alt),
                                suffixIcon: IconButton( // Add browse button
                                  icon: const Icon(Icons.more_horiz),
                                  tooltip: 'Browse',
                                  onPressed: _pickGameLibraryPath,
                                ),
                              ),
                              readOnly: true, // Make field read-only, use button to change
                              onTap: _pickGameLibraryPath, // Allow tapping field to browse too
                              // No validator needed, empty string is handled in _saveSettings
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Image Cache Path Display
                    Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        leading: const Icon(Icons.image),
                        title: const Text('Image Cache Location'),
                        subtitle: Text(_imageCachePath),
                        // Optional: Add button to open directory?
                      ),
                    ),

                    // IGDB API Settings
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
