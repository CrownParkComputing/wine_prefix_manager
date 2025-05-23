import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart'; // Needed for Common Components Dialog
import 'common_components_dialog.dart'; // Import for confirmation dialog
import 'action_button.dart'; // Import the new ActionButton widget

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
    final bool isProton = prefix.type == PrefixType.proton;
    // Determine if DXVK/VKD3D can be installed/reinstalled
    // bool canInstallGraphics = prefix.type == PrefixType.wine || prefix.wineBuildPath?.contains('Kronek') == true;

    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0, top: 8.0),
      child: Wrap(
        spacing: 8.0, // Horizontal spacing between chips
        runSpacing: 4.0, // Vertical spacing between lines of chips
        children: <Widget>[
          ActionButton(
            icon: Icons.add_to_photos_outlined,
            label: 'Add Executable',
            onPressed: () => onAddExecutable(prefix),
          ),
          ActionButton(
            icon: Icons.construction_outlined,
            label: 'Winetricks GUI',
            onPressed: () => onRunWinetricksGui(prefix),
          ),
          ActionButton(
            icon: Icons.settings_applications_outlined,
            label: 'Winecfg',
            onPressed: () => onRunWinecfg(context, prefix),
          ),
          // ActionButton(
          //   icon: Icons.build_circle_outlined,
          //   label: 'Winetricks Verbs',
          //   onPressed: () => onShowWinetricksVerbs(context, prefix, settings!),
          // ), // Removed
          // ActionButton(
          //   icon: Icons.extension_outlined,
          //   label: 'Common Components',
          //   onPressed: () => onShowCommonComponents(context, prefix),
          // ), // Removed Common Components button
          ActionButton(
            icon: Icons.rule_folder_outlined, // Changed icon to be more generic
            label: 'Install Software',
            tooltip: 'Run an installer (e.g., setup.exe) in this prefix',
            onPressed: () => onRunInstaller(prefix),
          ),
          // ActionButton(
          //   icon: Icons.gamepad_outlined,
          //   label: 'Controller Fix',
          //   tooltip: 'Apply common controller fixes (XInput, DInput)',
          //   onPressed: () => onApplyControllerFix(context, prefix),
          // ), // Removed Controller Fix button
           ActionButton(
            icon: Icons.edit_note_outlined,
            label: 'Env Variables',
            tooltip: 'Edit environment variables for this prefix',
            onPressed: () => onEditEnvVariables(context, prefix),
          ),
          ActionButton(
            icon: Icons.folder_open_outlined,
            label: isProton ? 'Explore C: Drive' : 'Explore Files',
            tooltip: isProton ? 'Open the C: drive of this Proton prefix' : 'Explore host files mapped to this prefix',
            onPressed: () => onExploreHostFiles(prefix),
          ),
          ActionButton(
            icon: Icons.edit_outlined,
            label: 'Rename Prefix',
            onPressed: () => onRenamePrefix(context, prefix),
            isDestructive: false, 
          ),
          ActionButton(
            icon: Icons.delete_forever_outlined,
            label: 'Delete Prefix',
            onPressed: () => onDeletePrefix(context, prefix),
            isDestructive: true,
          ),
        ],
      ),
    );
  }
}