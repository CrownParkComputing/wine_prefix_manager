import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../theme/theme_provider.dart';
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
    final theme = Theme.of(context);
    final version = _packageInfo?.version ?? 'Loading...';
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'App Settings',
            onPressed: () => _showAppSettings(context),
          ),
        ],
      ),
      body: Center(
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
                'Developed by Jon Whittingham', // Updated with real developer name
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'CrownParkComputing', // Added company/organization name
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
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
      ),
    );
  }

  void _showAppSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AppSettingsDialog(),
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

class _AppSettingsDialog extends StatefulWidget {
  @override
  State<_AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends State<_AppSettingsDialog> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeProvider, SettingsProvider>(
      builder: (context, themeProvider, settingsProvider, child) {
        return AlertDialog(
          title: const Text('App Settings'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Dark Mode'),
                  subtitle: const Text('Use dark theme'),
                  value: themeProvider.isDarkMode,
                  onChanged: (value) {
                    themeProvider.toggleTheme();
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Application Info',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('Version'),
                  subtitle: FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Text('${snapshot.data!.version} (${snapshot.data!.buildNumber})');
                      }
                      return const Text('Loading...');
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: const Text('Prefix Directory'),
                  subtitle: Text(settingsProvider.settings.prefixDirectory),
                ),
                const SizedBox(height: 16),
                Text(
                  'Navigation',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Settings are now organized by page:'),
                const SizedBox(height: 4),
                const Text('• Home: Game library and IGDB settings'),
                const Text('• Manage: Wine component settings'),
                const Text('• Create/Manage: Prefix creation and settings'),
                const Text('• Files & Backup: File browsing and backup management'),
                const Text('• Logs: Log management settings'),
                const Text('• About: Theme and app settings'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
} 