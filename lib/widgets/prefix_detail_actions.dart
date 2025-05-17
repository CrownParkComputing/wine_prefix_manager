import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart'; // Needed for Common Components Dialog
import 'common_components_dialog.dart'; // Import for confirmation dialog

// Define callback types required by this widget
typedef PrefixActionCallback = void Function(WinePrefix prefix);
typedef PrefixContextActionCallback = void Function(BuildContext context, WinePrefix prefix);
// typedef PrefixSettingsActionCallback = void Function(BuildContext context, WinePrefix prefix, Settings settings); // No longer needed

class PrefixDetailActions extends StatelessWidget {
  final WinePrefix prefix;
  final Settings? settings; // Make settings nullable, check before use
  final PrefixActionCallback onAddExecutable;
  final PrefixContextActionCallback onRunWinecfg; // Needs context
  final PrefixActionCallback onRunWinetricksGui; // No context needed here
  // final PrefixContextActionCallback onShowWinetricksVerbs; // Removed
  final PrefixContextActionCallback onShowCommonComponents; // FIX: Changed type
  final PrefixActionCallback onRunInstaller;
  final PrefixActionCallback onExploreHostFiles; // Renamed callback for clarity
  final PrefixContextActionCallback onDeletePrefix; // Needs context
  final PrefixContextActionCallback onRenamePrefix; // Added callback for rename
  final PrefixContextActionCallback onApplyControllerFix; // Added callback for controller fix
  final PrefixContextActionCallback onEditEnvVariables; // Added callback for environment variables

  const PrefixDetailActions({
    Key? key,
    required this.prefix,
    required this.settings,
    required this.onAddExecutable,
    required this.onRunWinecfg,
    required this.onRunWinetricksGui,
    // required this.onShowWinetricksVerbs, // Removed
    required this.onShowCommonComponents, // FIX: Changed type
    required this.onRunInstaller,
    required this.onExploreHostFiles, // Renamed callback
    required this.onDeletePrefix,
    required this.onRenamePrefix, // Added rename callback
    required this.onApplyControllerFix, // Added controller fix callback
    required this.onEditEnvVariables, // Added env variables callback
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Helper to create IconButton with Tooltip
    Widget _buildIconButton(IconData icon, String tooltip, VoidCallback? onPressed, {Color? color}) {
      return Tooltip(
        message: tooltip,
        child: IconButton(
          icon: Icon(icon),
          onPressed: onPressed,
          color: color, // Allow custom color for delete button
          visualDensity: VisualDensity.compact, // Make buttons slightly smaller
          padding: const EdgeInsets.all(8.0), // Adjust padding if needed
          constraints: const BoxConstraints(), // Remove default constraints if needed
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0), // Adjusted padding
      child: Wrap(
        spacing: 4, // Reduced spacing
        runSpacing: 0, // No vertical spacing needed for icons
        alignment: WrapAlignment.start,
        children: [
          _buildIconButton(
            Icons.add_box_outlined, // Changed icon
            'Add Executable',
            () => onAddExecutable(prefix),
          ),
          _buildIconButton( // Added Rename Button
            Icons.edit_outlined,
            'Rename Prefix',
            () => onRenamePrefix(context, prefix), // Call new callback
          ),
          _buildIconButton(
            Icons.settings_applications_outlined, // Changed icon
            'Run winecfg',
            () => onRunWinecfg(context, prefix), // Pass context
          ),
          _buildIconButton(
            Icons.handyman_outlined, // Changed icon
            'Run Winetricks GUI',
            () => onRunWinetricksGui(prefix), // Don't pass context
          ),
          // Removed Winetricks Verbs button
          _buildIconButton(
            Icons.build_circle_outlined, // Changed icon
            'Install Common Components',
            // FIX: Remove settings! argument from call
            () => onShowCommonComponents(context, prefix),
          ),
          _buildIconButton(
            Icons.terminal_outlined, // Changed icon
            'Run Installer (.exe/.msi)',
            () => onRunInstaller(prefix),
          ),
          _buildIconButton(
            Icons.folder_open_outlined, // Changed icon
            'Explore Prefix (Wine Explorer)', // Updated tooltip
            () => onExploreHostFiles(prefix), // Callback name updated for clarity
          ),
          _buildIconButton(
            Icons.sports_esports_outlined, // Controller/gamepad icon
            'Apply Controller Fix',
            () { // Show confirmation before applying
              showConfirmationDialog(
                context: context,
                title: 'Apply Controller Fix?',
                content: Text('Apply registry changes to improve controller support in "${prefix.name}"?'
                    '\n\nThis will add settings to enable SDL and disable Hidraw for better controller compatibility.'),
                confirmButtonText: 'Apply',
                onConfirm: () => onApplyControllerFix(context, prefix),
              );
            },
          ),
          _buildIconButton(
            Icons.tune_outlined, // Environment variables icon
            'Environment Variables',
            () => onEditEnvVariables(context, prefix),
          ),
          _buildIconButton(
            Icons.delete_forever_outlined, // Changed icon
            'Delete Prefix',
            () { // Modified onPressed for confirmation
              showConfirmationDialog(
                context: context,
                title: 'Delete Prefix?',
                content: Text('Are you sure you want to permanently delete the prefix "${prefix.name}" and all its contents?\n\nThis action cannot be undone.'),
                confirmButtonText: 'Delete',
                onConfirm: () => onDeletePrefix(context, prefix), // Call original callback on confirm
              );
            },
            color: Theme.of(context).colorScheme.error, // Use error color
          ),
        ],
      ),
    );
  }
}