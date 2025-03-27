import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';
import '../models/wine_build.dart';
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
  Settings? _settings;
  bool _isLoading = true;
  CoverSize _selectedCoverSize = CoverSize.medium;

  @override
  void initState() {
    super.initState();
    _prefixDirController = TextEditingController();
    _igdbClientIdController = TextEditingController();
    _igdbClientSecretController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _prefixDirController.dispose();
    _igdbClientIdController.dispose();
    _igdbClientSecretController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    final settings = await AppSettings.load();

    setState(() {
      _settings = settings;
      _prefixDirController.text = settings.prefixDirectory;
      _igdbClientIdController.text = settings.igdbClientId;
      _igdbClientSecretController.text = settings.igdbClientSecret;
      _selectedCoverSize = settings.coverSize;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      final settings = Settings(
        prefixDirectory: _prefixDirController.text,
        igdbClientId: _igdbClientIdController.text,
        igdbClientSecret: _igdbClientSecretController.text,
        igdbAccessToken: _settings?.igdbAccessToken,
        igdbTokenExpiry: _settings?.igdbTokenExpiry,
        coverSize: _selectedCoverSize, // Save selected cover size
        categories: _settings!.categories,
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
                        _settings = Settings(
                          prefixDirectory: _settings!.prefixDirectory,
                          igdbClientId: _settings!.igdbClientId,
                          igdbClientSecret: _settings!.igdbClientSecret,
                          igdbAccessToken: _settings!.igdbAccessToken,
                          igdbTokenExpiry: _settings!.igdbTokenExpiry,
                          coverSize: _settings!.coverSize,
                          categories: updatedCategories,
                        );
                      });
                      _saveSettings();
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
                    _settings = Settings(
                      prefixDirectory: _settings!.prefixDirectory,
                      igdbClientId: _settings!.igdbClientId,
                      igdbClientSecret: _settings!.igdbClientSecret,
                      igdbAccessToken: _settings!.igdbAccessToken,
                      igdbTokenExpiry: _settings!.igdbTokenExpiry,
                      coverSize: _settings!.coverSize,
                      categories: updatedCategories,
                    );
                  });
                  _saveSettings();
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
                              'Directories',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _prefixDirController,
                              decoration: const InputDecoration(
                                labelText: 'Prefix Directory',
                                helperText:
                                    'Main directory where prefixes are stored',
                                prefixIcon: Icon(Icons.folder),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a directory path';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
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
