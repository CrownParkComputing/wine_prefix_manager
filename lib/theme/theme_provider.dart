import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;
  ThemeData get themeData => _isDarkMode ? _darkTheme : _lightTheme;

  ThemeProvider() {
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final file = _getSettingsFile();
    try {
      if (await file.exists()) {
        final contents = await file.readAsString();
        final data = jsonDecode(contents);
        _isDarkMode = data['darkMode'] ?? false;
        notifyListeners();
      }
    } catch (e) {
      print('Error loading theme settings: $e');
    }
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    
    try {
      final file = _getSettingsFile();
      await file.writeAsString(jsonEncode({'darkMode': _isDarkMode}));
    } catch (e) {
      print('Error saving theme settings: $e');
    }
  }

  File _getSettingsFile() {
    final homeDir = Platform.environment['HOME']!;
    return File(path.join(homeDir, '.wine_prefix_manager_theme.json'));
  }

  // Light theme
  static final _lightTheme = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.light,
    ),
  );

  // Dark theme
  static final _darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.dark,
    ),
  );
}
