import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Provider class for window control buttons to centralize window management
/// and prevent duplicate controls across different pages
class WindowControlProvider {
  /// Get window control buttons as a list of widgets
  List<Widget> getWindowButtons() {
    return [
      IconButton(
        icon: const Icon(Icons.minimize),
        onPressed: () => windowManager.minimize(),
        tooltip: 'Minimize',
      ),
      IconButton(
        icon: const Icon(Icons.crop_square),
        onPressed: () async {
          if (await windowManager.isMaximized()) {
            windowManager.unmaximize();
          } else {
            windowManager.maximize();
          }
        },
        tooltip: 'Maximize',
      ),
      IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => windowManager.close(),
        tooltip: 'Close',
      ),
    ];
  }
}
