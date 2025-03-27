import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class CustomTitleBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool isConnected; // Add connectivity status
  final Color? backgroundColor; // Optional background color
 
  const CustomTitleBar({
    super.key,
    required this.title,
    required this.isConnected, // Make it required
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleBarColor = backgroundColor ?? theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary;
    final iconColor = theme.colorScheme.onPrimary; // Adjust if needed based on titleBarColor contrast

    return GestureDetector(
      onPanStart: (details) {
        windowManager.startDragging();
      },
      child: Container(
        height: preferredSize.height,
        color: titleBarColor,
        child: Row(
          children: [
            // Optional: Add an icon or padding at the start
            const SizedBox(width: 16),
            // Title
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(color: iconColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Connectivity Indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Icon(
                isConnected ? Icons.wifi : Icons.wifi_off,
                color: isConnected ? iconColor : Colors.orangeAccent, // Different color when offline
                size: 18, // Smaller icon size
              ),
            ),
            // Window Control Buttons
            MinimizeButton(color: iconColor),
            MaximizeRestoreButton(color: iconColor),
            CloseButton(color: iconColor),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight); // Standard AppBar height
}

// --- Button Widgets ---

class MinimizeButton extends StatelessWidget {
  final Color? color;
  const MinimizeButton({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.minimize),
      color: color,
      tooltip: 'Minimize',
      onPressed: () => windowManager.minimize(),
    );
  }
}

class MaximizeRestoreButton extends StatefulWidget {
  final Color? color;
  const MaximizeRestoreButton({super.key, this.color});

  @override
  State<MaximizeRestoreButton> createState() => _MaximizeRestoreButtonState();
}

class _MaximizeRestoreButtonState extends State<MaximizeRestoreButton> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    // Listen to maximize/unmaximize events to update the icon
    windowManager.isMaximized().then((value) {
      if (mounted) {
        setState(() {
          _isMaximized = value;
        });
      }
    });
    // Add listener (consider using WindowListener mixin for more robust handling)
    // This basic approach might miss some edge cases.
    // A more robust solution would involve implementing WindowListener.
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_isMaximized ? Icons.fullscreen_exit : Icons.fullscreen),
      color: widget.color,
      tooltip: _isMaximized ? 'Restore' : 'Maximize',
      onPressed: () async {
        bool isMax = await windowManager.isMaximized();
        if (isMax) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
        // Update state after action
        if (mounted) {
          setState(() {
            _isMaximized = !isMax;
          });
        }
      },
    );
  }
}


class CloseButton extends StatelessWidget {
  final Color? color;
  const CloseButton({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.close),
      color: color,
      tooltip: 'Close',
      onPressed: () => windowManager.close(),
    );
  }
}