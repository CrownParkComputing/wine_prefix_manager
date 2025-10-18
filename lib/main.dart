import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Models
import 'models/settings.dart';
import 'models/prefix_models.dart'; // Import Prefix models for callbacks

// Providers
import 'providers/prefix_provider.dart';
import 'providers/window_control_provider.dart';
import 'providers/settings_provider.dart';
import 'theme/theme_provider.dart';

// Services
import 'services/prefix_management_service.dart';
import 'services/prefix_creation_service.dart';
import 'services/process_service.dart';
import 'services/log_service.dart';
import 'services/igdb_service.dart'; // Import IgdbService
import 'services/ui_action_service.dart'; // Import UIActionService
import 'services/compressed_game_service.dart'; // Import CompressedGameService
import 'services/power_management_service.dart';
import 'services/category_service.dart'; // Import CategoryService

// Widgets & Pages
// import 'widgets/custom_title_bar.dart'; // Removed import
import 'pages/home_page.dart';
import 'pages/manage_prefixes_page.dart';
// import 'pages/prefix_management_page.dart'; // Removed - functionality integrated into ManagePrefixesPage
import 'pages/logs_page.dart';
// Add import for GameListViewPage
// Import RenamePrefixDialog
import 'widgets/env_variables_dialog.dart'; // Add import for environment variables dialog
import 'pages/game_details_page.dart'; // Add import for GameDetailsPage
import 'widgets/about_screen.dart'; // Correct import for AboutScreen
import 'pages/files_and_backup_page.dart'; // Add import for FilesAndBackupPage
import 'pages/settings_page.dart';

// Utils
import 'utils/logger.dart';
import 'utils/path_utils.dart';

/// Migrate legacy string-based categories to new CategoryService
Future<void> _migrateLegacyCategories(Settings settings) async {
  try {
    // Import any old categories from settings that don't exist in CategoryService
    if (settings.categories.isNotEmpty) {
      await CategoryService.importFromStringList(settings.categories);
    }
  } catch (e) {
    logError('Failed to migrate legacy categories: $e');
  }
}

// Constants
// const String appTitle = 'Wine Prefix Manager'; // Removed

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Initialize environment variables
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    // .env file not found or couldn't be loaded - this is fine for production
    // where environment variables are set directly
    logInfo('Note: .env file not found or could not be loaded. Using system environment variables.');
  }

  // Configure window options
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'Wine Prefix Manager',
  );

  // Show window after options are set
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Initialize Settings using AppSettings.load()
  final settings = await AppSettings.load(); // FIX: Use AppSettings.load()
  // Initialize ThemeProvider using default constructor
  final themeProvider = ThemeProvider(); // FIX: Use default constructor
  final logService = LogService(); // Create LogService instance
  await logService.initialize(); // Initialize LogService
  
  // Initialize CategoryService with the app data directory
  final baseAppDataPath = await getBaseAppDataPath();
  await CategoryService.initialize(baseAppDataPath);
  
  // Migrate old string-based categories to new CategoryService
  await _migrateLegacyCategories(settings);

  runApp(
    MultiProvider(
      providers: [
        // State Management Providers
        // Note: PrefixProvider needs to be created before UIActionService if UIActionService depends on it
        ChangeNotifierProvider(create: (_) => PrefixProvider()),
        // FIX: Use Provider for WindowControlProvider as it doesn't notify
        Provider(create: (_) => WindowControlProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
        // Add SettingsProvider for reactive settings updates
        ChangeNotifierProvider(create: (_) => SettingsProvider(settings)),
        // Keep providing Settings directly for backward compatibility
        Provider.value(value: settings),

        // Service Providers (Singletons)
        Provider.value(value: logService), // Provide LogService instance
        Provider(create: (_) => PrefixManagementService()),
        Provider(create: (_) => PrefixCreationService()),
        Provider(create: (_) => CompressedGameService()),
        Provider<PowerManagementService>(
          create: (context) => PowerManagementService(context.read<LogService>()),
        ),
        Provider(create: (context) => ProcessService(
          compressedGameService: Provider.of<CompressedGameService>(context, listen: false),
          powerManagementService: Provider.of<PowerManagementService>(context, listen: false),
        )),
        Provider(create: (_) => IgdbService()),
        Provider(create: (context) => UIActionService(
          logService: Provider.of<LogService>(context, listen: false),
          igdbService: Provider.of<IgdbService>(context, listen: false),
          processService: Provider.of<ProcessService>(context, listen: false),
          prefixProvider: Provider.of<PrefixProvider>(context, listen: false), // Inject PrefixProvider
          settings: Provider.of<SettingsProvider>(context, listen: false).settings, // Get settings from provider
        )),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Settings _settings;
  late final LogService _logService;
  // Removed IgdbService and PrefixProvider instance variables as they are mainly used via UIActionService now
  // late final IgdbService _igdbService;
  // late final PrefixProvider _prefixProvider;

  @override
  void initState() {
    super.initState();
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _settings = settingsProvider.settings;
    _logService = Provider.of<LogService>(context, listen: false);
    // _igdbService = Provider.of<IgdbService>(context, listen: false); // No longer needed here
    final prefixProvider = Provider.of<PrefixProvider>(context, listen: false); // Get provider instance

    // FIX: Delay provider updates until after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) { // Check if the widget is still in the tree
        // Update providers with initial settings
        prefixProvider.updateSettings(_settings); // Pass settings to PrefixProvider
        // Load prefixes after settings are available
        prefixProvider.loadPrefixes();
        // Scan for any new prefixes that might not be in the saved state
        prefixProvider.scanForPrefixes();
      }
    });

    // FIX: Use _logService.log instead of addLog
    _logService.log('Application started.');
    // _logService.log('Theme Mode: ${_settings.themeMode.name}'); // FIX: themeMode removed from Settings
    _logService.log('Prefix Directory: ${_settings.prefixDirectory}');
    _logService.log('Wine Builds API URL: ${_settings.wineBuildsApiUrl}'); // FIX: Use wineBuildsApiUrl
    _logService.log('Proton GE API URL: ${_settings.protonGeApiUrl}'); // FIX: Use protonGeApiUrl (example)
    _logService.log('Game Library Path: ${_settings.gameLibraryPath ?? 'Default'}');
    _logService.log('Using global IGDB Client ID and Secret.');
    _logService.log('IGDB Image Base URL: ${_settings.igdbImageBaseUrl}');
    _logService.log('Twitch OAuth URL: ${_settings.twitchOAuthUrl}');
    _logService.log('IGDB API Base URL: ${_settings.igdbApiBaseUrl}');
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Removed unused _addLogMessage method

  @override
  Widget build(BuildContext context) {
    // Use Consumer for ThemeProvider to react to theme changes
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Wine Prefix Manager',
          home: const MainScaffold(), // MainScaffold is the home
          theme: themeProvider.themeData, 
          themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light, 
          debugShowCheckedModeBanner: false,
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case '/':
                return MaterialPageRoute(builder: (context) => const MainScaffold());
              case '/game_details':
                if (settings.arguments is GameEntry) {
                  final game = settings.arguments as GameEntry;
                  // Get required services from context
                  final prefixProvider = Provider.of<PrefixProvider>(context, listen: false);
                  final uiActionService = Provider.of<UIActionService>(context, listen: false);
                  final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
                  
                  return MaterialPageRoute(
                    builder: (context) => GameDetailsPage(
                      game: game,
                      settings: settingsProvider.settings,
                      availablePrefixes: prefixProvider.prefixes,
                      onLaunchGame: () {
                        Navigator.of(context).pop(); // Go back after launch
                        uiActionService.launchGame(game);
                      },
                      onToggleWorkingStatus: (game, notWorking) async {
                        // Update working status via prefix provider
                        final updatedExe = game.exe.copyWith(notWorking: notWorking);
                        await prefixProvider.updateExecutable(game.prefix, updatedExe);
                      },
                      onChangeCategory: (game, category) async {
                        // Update category via prefix provider
                        final updatedExe = game.exe.copyWith(category: category);
                        await prefixProvider.updateExecutable(game.prefix, updatedExe);
                      },
                      onEditExePath: (game) async {
                        // Simple placeholder - just log for now
                        final logService = Provider.of<LogService>(context, listen: false);
                        logService.log('Edit exe path requested for ${game.exe.name}');
                      },
                      onUpdateMetadata: (game) async {
                        // Simple placeholder - just log for now
                        final logService = Provider.of<LogService>(context, listen: false);
                        logService.log('Update metadata requested for ${game.exe.name}');
                      },
                      onSaveLaunchOptions: (game, options) async {
                        // Update launch options via prefix provider
                        final updatedExe = game.exe.copyWith(launchOptions: options);
                        await prefixProvider.updateExecutable(game.prefix, updatedExe);
                      },
                    ),
                  );
                }
                return MaterialPageRoute(builder: (context) => const MainScaffold());
              default:
                return MaterialPageRoute(builder: (context) => const MainScaffold());
            }
          },
          routes: const {
            // Routes are now handled through main scaffold navigation
            // Keeping only essential routes if needed by other parts of the app
          },
        );
      },
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0; // Default to Home (Game Library) which is index 0
  late final UIActionService _uiActionService;
  final Map<String, int> _runningProcesses = {}; // State for running processes
  
  // Method to switch tabs - can be accessed from outside via a callback
  void navigateToTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void initState() {
     super.initState();
     // _settings = Provider.of<Settings>(context, listen: false); // No longer needed here if only used in dialogs via service
     // _logService = Provider.of<LogService>(context, listen: false); // No longer needed if _addLogMessage is removed
     // _igdbService = Provider.of<IgdbService>(context, listen: false); // No longer needed here
     // _prefixProvider = Provider.of<PrefixProvider>(context, listen: false); // No longer needed here
     _uiActionService = Provider.of<UIActionService>(context, listen: false); // Initialize UIActionService
  }

  // Callback for when a process starts
  void _onProcessStart(String exePath, int pid) {
    setState(() {
      _runningProcesses[exePath] = pid;
    });
  }

  // Callback for when a process exits
  void _onProcessExit(String exePath, int exitCode, List<String> errors) {
    setState(() {
      _runningProcesses.remove(exePath);
    });
    // Optionally show errors or exit code to user via snackbar or log
    final logService = Provider.of<LogService>(context, listen: false);
    logService.log('Process $exePath exited with code $exitCode.');
    if (errors.isNotEmpty) {
      logService.log('Process errors: ${errors.join('\n')}', LogLevel.warning);
    }
  }


  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildPage(int index) {
    final prefixProvider = Provider.of<PrefixProvider>(context, listen: false);
    final processService = Provider.of<ProcessService>(context, listen: false);
    final prefixManagementService = Provider.of<PrefixManagementService>(context, listen: false);
    final logService = Provider.of<LogService>(context, listen: false);
    // Access SettingsProvider for settings
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false); 
    
    switch (index) {
      case 0:
        return HomePage(
          onNavigateToTab: navigateToTab,
        );
      case 1:
        // Use settings from SettingsProvider
        return ManagePrefixesPage(
          settings: settingsProvider.settings, 
          onAddExecutable: (prefix) => _uiActionService.addExecutableToPrefix(context, prefix),
          onShowCommonComponents: (context, prefix) => _uiActionService.showCommonComponentsDialog(context, prefix),
          onDeletePrefix: (ctx, pfx) => prefixProvider.deletePrefix(pfx),
          onDeleteExecutable: (ctx, pfx, exe) => prefixProvider.deleteExecutable(pfx, exe),
          onRenamePrefix: (ctx, pfx, newName) async {
            try {
              await prefixProvider.renamePrefix(pfx, newName);
              if (mounted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Prefix renamed to "$newName"')),
                );
              }
            } catch (e) {
              if (mounted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error renaming prefix: $e'), backgroundColor: Theme.of(context).colorScheme.error),
                );
              }
            }
          },
          onApplyControllerFix: (ctx, pfx) async {
            try {
              await prefixManagementService.applyControllerFix(pfx, onStatusUpdate: (status) {
                logService.log('Controller Fix: $status');
              });
              if (mounted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Controller fixes applied to "${pfx.name}"')),
                );
              }
            } catch (e) {
              if (mounted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error applying controller fixes: $e'), backgroundColor: Theme.of(context).colorScheme.error),
                );
              }
            }
          },
          onRunExe: (pfx, exe) async {
            try {
              await processService.runExecutable(
                pfx,
                exe,
                onProcessStart: _onProcessStart,
                onProcessExit: _onProcessExit,
              );
            } catch (e) {
              logService.log('Error running executable ${exe.name}: $e', LogLevel.error);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error running ${exe.name}: $e')),
                );
              }
            }
          },
          onKillProcess: (pfx, exe) async {
            final pid = _runningProcesses[exe.path];
            if (pid != null) {
              logService.log('Attempting to kill ${exe.name} (PID: $pid)...');
              
              // Try graceful termination with process tree killing first
              bool success = await processService.killProcess(pid, killTree: true);
              
              if (!success) {
                logService.log('Graceful termination failed, trying force kill...', LogLevel.warning);
                // If graceful kill fails, try force kill
                success = await processService.killProcess(pid, force: true, killTree: true);
              }
              
              if (!success) {
                logService.log('Individual process kill failed, trying wine-specific cleanup...', LogLevel.warning);
                // Last resort: try to kill all wine processes for this prefix
                success = await processService.killAllWineProcesses(pfx);
              }
              
              if (success) {
                logService.log('Successfully terminated ${exe.name} (PID: $pid)');
                // Remove from tracking immediately
                setState(() {
                  _runningProcesses.remove(exe.path);
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${exe.name} has been terminated'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } else {
                logService.log('Failed to kill ${exe.name} (PID: $pid) - all methods exhausted', LogLevel.error);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to kill process for ${exe.name}. Try using system process manager.'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            } else {
              logService.log('Process for ${exe.name} not found in running list - attempting wine cleanup...', LogLevel.warning);
              // Try wine-specific cleanup even without PID tracking
              final success = await processService.killAllWineProcesses(pfx);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Attempted cleanup of wine processes for ${exe.name}'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }
          },
          runningProcesses: _runningProcesses,
          onRunWinetricksGui: (pfx) => Provider.of<PrefixManagementService>(context, listen: false).runWinetricksGui(pfx),
          onRunInstaller: (pfx) => _uiActionService.runInstallerInPrefix(context, pfx),
          onExploreHostFiles: (pfx) => _uiActionService.explorePrefixFiles(pfx),
          onRunWinecfg: (ctx, pfx) => Provider.of<PrefixManagementService>(context, listen: false).runWinecfg(pfx),
          onEditEnvVariables: (ctx, pfx) async {
            final result = await showDialog<Map<String, String>>(
              context: ctx,
              builder: (_) => EnvVariablesDialog(prefix: pfx),
            );
            if (result != null && mounted) {
              await prefixProvider.updatePrefix(pfx.copyWith(environmentVariables: result));
            }
          },
          onKillAllProcesses: (ctx, pfx) async {
            final confirmed = await showDialog<bool>(
              context: ctx,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Kill All Wine Processes'),
                content: Text('Kill all Wine/Proton processes for prefix "${pfx.name}"?\n\nThis will terminate all running games and applications in this prefix.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Kill All'),
                  ),
                ],
              ),
            );
            
            if (confirmed == true) {
              logService.log('Attempting to kill all Wine processes for prefix: ${pfx.name}');
              final success = await processService.killAllWineProcesses(pfx);
              
              if (success) {
                logService.log('Successfully killed all Wine processes for prefix: ${pfx.name}');
                // Clear tracking for all processes from this prefix
                setState(() {
                  _runningProcesses.removeWhere((path, pid) => 
                    pfx.exeEntries.any((exe) => exe.path == path));
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Killed all Wine processes for ${pfx.name}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } else {
                logService.log('Failed to kill all Wine processes for prefix: ${pfx.name}', LogLevel.error);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to kill Wine processes for ${pfx.name}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }
          },
        );
      case 2:
        // Combined Files & Backup Manager - tabbed interface
        return const FilesAndBackupPage();
      case 3:
        return const LogsPage();
      case 4:
        return const SettingsPage();
      case 5:
        return const AboutScreen();
      default:
        return HomePage(onNavigateToTab: navigateToTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final selectedColor = isDarkMode ? theme.colorScheme.primary : theme.colorScheme.onPrimary;
    final unselectedColor = isDarkMode ? theme.colorScheme.onSurface.withValues(alpha:0.7) : theme.colorScheme.onSurface.withValues(alpha:0.6);
    final railBackgroundColor = theme.colorScheme.surface;

    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: <Widget>[
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onItemTapped,
                  labelType: NavigationRailLabelType.selected,
                  backgroundColor: railBackgroundColor,
                  indicatorColor: theme.colorScheme.primaryContainer.withValues(alpha:0.3),
                  selectedIconTheme: IconThemeData(color: selectedColor),
                  unselectedIconTheme: IconThemeData(color: unselectedColor),
                  selectedLabelTextStyle: TextStyle(color: selectedColor, fontWeight: FontWeight.bold),
                  unselectedLabelTextStyle: TextStyle(color: unselectedColor),
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.folder_outlined),
                      selectedIcon: Icon(Icons.folder),
                      label: Text('Manage'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.folder_copy_outlined),
                      selectedIcon: Icon(Icons.folder_copy),
                      label: Text('Files & Backup'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.article_outlined),
                      selectedIcon: Icon(Icons.article),
                      label: Text('Logs'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.info_outline),
                      selectedIcon: Icon(Icons.info),
                      label: Text('About'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: Builder(
                    builder: (context) => _buildPage(_selectedIndex),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Dialog and Action Handlers ---

  // REMOVED _showCommonComponentsDialog method from here

} // End _MainScaffoldState
