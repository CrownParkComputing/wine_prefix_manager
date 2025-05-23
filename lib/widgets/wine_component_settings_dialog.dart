import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';
import '../providers/settings_provider.dart';
import '../services/log_service.dart';

class WineComponentSettingsDialog extends StatefulWidget {
  const WineComponentSettingsDialog({Key? key}) : super(key: key);

  @override
  State<WineComponentSettingsDialog> createState() => _WineComponentSettingsDialogState();
}

class _WineComponentSettingsDialogState extends State<WineComponentSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  Settings? _settings;
  bool _isLoading = true;

  // Controllers for URL settings
  late TextEditingController _dxvkApiUrlController;
  late TextEditingController _vkd3dApiUrlController;
  late TextEditingController _wineBuildsApiUrlController;
  late TextEditingController _protonGeApiUrlController;
  late TextEditingController _kronekProtonApiUrlController;

  @override
  void initState() {
    super.initState();
    // Initialize controllers
    _dxvkApiUrlController = TextEditingController();
    _vkd3dApiUrlController = TextEditingController();
    _wineBuildsApiUrlController = TextEditingController();
    _protonGeApiUrlController = TextEditingController();
    _kronekProtonApiUrlController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    // Dispose controllers
    _dxvkApiUrlController.dispose();
    _vkd3dApiUrlController.dispose();
    _wineBuildsApiUrlController.dispose();
    _protonGeApiUrlController.dispose();
    _kronekProtonApiUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final currentSettings = settingsProvider.settings;

    if (!mounted) return;
    setState(() {
      _settings = currentSettings;
      _dxvkApiUrlController.text = currentSettings.dxvkApiUrl;
      _vkd3dApiUrlController.text = currentSettings.vkd3dApiUrl;
      _wineBuildsApiUrlController.text = currentSettings.wineBuildsApiUrl;
      _protonGeApiUrlController.text = currentSettings.protonGeApiUrl;
      _kronekProtonApiUrlController.text = currentSettings.kronekProtonApiUrl;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
      });

      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      final currentSettings = settingsProvider.settings;
      final logService = Provider.of<LogService>(context, listen: false);

      final newSettings = currentSettings.copyWith(
        dxvkApiUrl: _dxvkApiUrlController.text.trim(),
        vkd3dApiUrl: _vkd3dApiUrlController.text.trim(),
        wineBuildsApiUrl: _wineBuildsApiUrlController.text.trim(),
        protonGeApiUrl: _protonGeApiUrlController.text.trim(),
        kronekProtonApiUrl: _kronekProtonApiUrlController.text.trim(),
      );

      try {
        await settingsProvider.updateSettings(newSettings);
        logService.log('Wine component settings updated successfully.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Wine component settings saved!')),
          );
          Navigator.of(context).pop(); // Close dialog on success
        }
      } catch (e) {
        logService.log('Failed to save Wine component settings: $e', LogLevel.error);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving settings: $e'), backgroundColor: Colors.red),
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

  Widget _buildUrlSettingField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
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
          prefixIcon: icon != null ? Icon(icon) : null,
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'URL cannot be empty';
          }
          if (!(Uri.tryParse(value.trim())?.isAbsolute == true)) {
            return 'Please enter a valid URL';
          }
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Loading settings...'),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: const Text('Wine Component Settings'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildUrlSettingField(
                controller: _dxvkApiUrlController,
                label: 'DXVK Releases API URL',
                hint: 'e.g., https://api.github.com/repos/doitsujin/dxvk/releases',
                icon: Icons.code,
              ),
              _buildUrlSettingField(
                controller: _vkd3dApiUrlController,
                label: 'VKD3D-Proton Releases API URL',
                hint: 'e.g., https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases',
                icon: Icons.code_off,
              ),
              _buildUrlSettingField(
                controller: _wineBuildsApiUrlController,
                label: 'Kronek Wine Builds API URL',
                hint: 'e.g., https://api.github.com/repos/Kron4ek/Wine-Builds/releases',
                icon: Icons.wine_bar,
              ),
              _buildUrlSettingField(
                controller: _protonGeApiUrlController,
                label: 'Proton-GE Releases API URL',
                hint: 'e.g., https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases',
                icon: Icons.gamepad,
              ),
              _buildUrlSettingField(
                controller: _kronekProtonApiUrlController,
                label: 'Kronek Proton Builds API URL',
                hint: 'e.g., https://api.github.com/repos/Kron4ek/Proton-Wine-Builds/releases',
                icon: Icons.rocket_launch,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveSettings,
          child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ],
    );
  }
} 