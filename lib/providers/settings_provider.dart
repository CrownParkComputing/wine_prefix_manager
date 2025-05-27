import 'package:flutter/material.dart';
import '../models/settings.dart';

/// Provider class for application settings
/// This allows for reactive updates when settings change
class SettingsProvider extends ChangeNotifier {
  Settings _settings;

  SettingsProvider(this._settings);

  Settings get settings => _settings;

  /// Updates settings and notifies listeners
  Future<void> updateSettings(Settings settings) async {
    _settings = settings;
    await AppSettings.save(_settings);
    notifyListeners();
  }

  /// Updates settings and notifies listeners
  Future<void> updateIgdbToken(String token, Duration expiry) async {
    final updatedSettings = await AppSettings.updateToken(_settings, token, expiry);
    _settings = updatedSettings;
    notifyListeners();
  }
}
