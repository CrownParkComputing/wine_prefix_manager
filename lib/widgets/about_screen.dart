import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';
import '../models/prefix_models.dart';
import '../providers/prefix_provider.dart';
import '../providers/settings_provider.dart';
// import '../services/ui_action_service.dart'; // Likely not needed for a pure About screen
import 'package:package_info_plus/package_info_plus.dart';
// import 'action_button.dart'; // Likely not needed if quick actions are removed

class AboutScreen extends StatefulWidget {
  // These might not be needed if the About screen is purely informational
  // final List<WinePrefix> prefixes;
  // final Settings settings;
  // final VoidCallback onNavigateToCreatePrefix;
  // final VoidCallback onNavigateToSettings;
  
  const AboutScreen({
    Key? key,
    // required this.prefixes,
    // required this.settings,
    // required this.onNavigateToCreatePrefix,
    // required this.onNavigateToSettings,
  }) : super(key: key);

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _packageInfo;
  // bool _hasActivePrompt = false; // Removed as setup prompts are removed

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    // Setup-related calls removed
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   _checkSetupIssues();
    //   _validateIgdbCredentials(context);
    // });
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _packageInfo = packageInfo;
      });
    }
  }

  // Setup-related methods commented out or removed
  // void _checkSetupIssues() { ... }
  // void _showSetupPrefixDialog() { ... }
  // void _showSetupIgdbDialog() { ... }
  // void _validateIgdbCredentials(BuildContext context) async { ... }

  // @override
  // void didUpdateWidget(AboutScreen oldWidget) { // Changed from WelcomeScreen to AboutScreen
  //   super.didUpdateWidget(oldWidget);
  //   // if (widget.settings.igdbClientId != oldWidget.settings.igdbClientId ||
  //   //     widget.settings.igdbClientSecret != oldWidget.settings.igdbClientSecret) {
  //   //   _checkSetupIssues(); 
  //   // }
  // }
  
  @override
  Widget build(BuildContext context) {
    // final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    // final settings = settingsProvider.settings;
    final theme = Theme.of(context);
    final version = _packageInfo?.version ?? 'Loading...';
    
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline, // Changed icon to reflect 'About'
              size: 100,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Wine Prefix Manager',
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              'Version $version',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              'This application helps you manage your Wine and Proton prefixes for running Windows games and applications on Linux.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text(
              'Developed by: [Your Name/Organization]', // Placeholder for actual developer name
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Powered by Flutter & Dart',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            // Status Card and Quick Actions removed for a cleaner About screen
            /*
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // _buildStatusItem(...),
                    // const Divider(),
                    // _buildStatusItem(...),
                    // const Divider(),
                    // _buildStatusItem(...),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              'Quick Actions',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 16,
              children: [
                // ActionButton(...),
                // ActionButton(...),
              ],
            ),
            */
          ],
        ),
      ),
    );
  }
  
  // _buildStatusItem method might not be needed if Status Card is removed
  /*
  Widget _buildStatusItem(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
    [VoidCallback? onTap]
  ) {
    final isClickable = onTap != null;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            if (isClickable) Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }
  */
} 