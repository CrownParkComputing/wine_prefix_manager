import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';
import '../models/prefix_models.dart';
import '../providers/prefix_provider.dart';
import '../providers/settings_provider.dart';
import '../services/ui_action_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

class WelcomeScreen extends StatefulWidget {
  final List<WinePrefix> prefixes;
  final Settings settings;
  final VoidCallback onNavigateToCreatePrefix;
  final VoidCallback onNavigateToSettings;
  
  const WelcomeScreen({
    Key? key,
    required this.prefixes,
    required this.settings,
    required this.onNavigateToCreatePrefix,
    required this.onNavigateToSettings,
  }) : super(key: key);

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  PackageInfo? _packageInfo;
  bool _hasActivePrompt = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    // Check for setup issues after first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSetupIssues();
      // Also validate IGDB credentials when the widget initializes
      _validateIgdbCredentials(context);
    });
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _packageInfo = packageInfo;
      });
    }
  }

  void _checkSetupIssues() {
    if (_hasActivePrompt || !mounted) return; // Prevent multiple prompts and check if mounted
    
    // Check if there are no prefixes
    if (widget.prefixes.isEmpty) {
      setState(() => _hasActivePrompt = true);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {  // Check if still mounted before showing dialog
          _showSetupPrefixDialog();
        }
      });
      return;
    }

    // Use widget.settings directly to avoid Provider issues
    if (widget.settings.igdbClientId.isEmpty || widget.settings.igdbClientSecret.isEmpty) {
      setState(() => _hasActivePrompt = true);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {  // Check if still mounted before showing dialog
          _showSetupIgdbDialog();
        }
      });
      return;
    }
  }

  void _showSetupPrefixDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('No Wine Prefixes Found'),
        content: const Text(
          'You need to create at least one Wine prefix to use this application. '
          'Would you like to create one now?'
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _hasActivePrompt = false);
            },
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _hasActivePrompt = false);
              widget.onNavigateToCreatePrefix();
            },
            child: const Text('Create Prefix'),
          ),
        ],
      ),
    );
  }

  void _showSetupIgdbDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('IGDB API Credentials Missing'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To fetch game information, cover art and screenshots, you need to configure '
              'IGDB API credentials in the settings. Would you like to set them up now?'
            ),
            SizedBox(height: 16),
            Text(
              'To get IGDB credentials:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('1. Create a Twitch Developer account'),
            Text('2. Register an application at dev.twitch.tv'),
            Text('3. Copy the Client ID and Client Secret'),
            Text('4. Enter them in the Settings page'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _hasActivePrompt = false);
            },
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _hasActivePrompt = false);
              widget.onNavigateToSettings();
            },
            child: const Text('Go to Settings'),
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(WelcomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If settings have changed, recheck setup issues
    if (widget.settings.igdbClientId != oldWidget.settings.igdbClientId ||
        widget.settings.igdbClientSecret != oldWidget.settings.igdbClientSecret) {
      _checkSetupIssues();
    }
  }
  
  // Method to validate IGDB credentials
  Future<void> _validateIgdbCredentials(BuildContext context) async {
    try {
      // Access settings directly via the widget property
      // Check if credentials are valid
      final isValid = widget.settings.igdbClientId.isNotEmpty && 
                       widget.settings.igdbClientSecret.isNotEmpty;
      
      if (mounted && isValid && _hasActivePrompt) {
        setState(() {
          _hasActivePrompt = false;
        });
      }
    } catch (e) {
      // Ignore errors during validation
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use watch to rebuild when settings change
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final settings = settingsProvider.settings;
    final theme = Theme.of(context);
    final version = _packageInfo?.version ?? 'Loading...';
    
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // App Logo/Icon
            Icon(
              Icons.wine_bar,
              size: 100,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            
            // App Title
            Text(
              'Wine Prefix Manager',
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
            
            // Version
            Text(
              'Version $version',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            
            const SizedBox(height: 48),
            
            // Status Card
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatusItem(
                      context,
                      'Wine Prefixes',
                      widget.prefixes.isEmpty ? 'Not Configured' : '${widget.prefixes.length} Available',
                      widget.prefixes.isEmpty ? Icons.error : Icons.check_circle,
                      widget.prefixes.isEmpty ? theme.colorScheme.error : Colors.green,
                      widget.prefixes.isEmpty ? widget.onNavigateToCreatePrefix : null,
                    ),
                    
                    const Divider(),
                    
                    _buildStatusItem(
                      context,
                      'IGDB Integration',
                      _hasIgdbCredentials() ? 'Configured' : 'Not Configured',
                      _hasIgdbCredentials() ? Icons.check_circle : Icons.warning,
                      _hasIgdbCredentials() ? Colors.green : Colors.orange,
                      _hasIgdbCredentials() ? null : widget.onNavigateToSettings,
                    ),
                    
                    const Divider(),
                    
                    _buildStatusItem(
                      context,
                      'Prefix Directory',
                      widget.settings.prefixDirectory,
                      Icons.folder,
                      theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 48),
            
            // Quick Actions
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
                _buildActionButton(
                  context,
                  'Create Prefix',
                  Icons.add_circle,
                  widget.onNavigateToCreatePrefix,
                ),
                _buildActionButton(
                  context,
                  'Settings',
                  Icons.settings,
                  widget.onNavigateToSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  bool _hasIgdbCredentials() {
    // Get the latest settings from the provider instead of using widget.settings
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final settings = settingsProvider.settings;
    return settings.igdbClientId.isNotEmpty && 
           settings.igdbClientSecret.isNotEmpty;
  }
  
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
  
  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    );
  }
}
