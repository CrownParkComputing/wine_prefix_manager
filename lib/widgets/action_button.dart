import 'package:flutter/material.dart';

class ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool isDestructive;

  const ActionButton({
    Key? key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.isDestructive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final buttonStyle = isDestructive
        ? ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          )
        : ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
          );

    final button = ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18), // Adjusted icon size for consistency
      label: Text(label),
      style: buttonStyle.copyWith(
        padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 8)), // Adjusted padding
      )
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: button,
      );
    }
    return button;
  }
} 