import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// Widgets & Pages
// import 'widgets/custom_title_bar.dart'; // Removed import
import 'pages/home_page.dart';
import 'pages/manage_prefixes_page.dart';
import 'pages/settings_page.dart';
import 'pages/logs_page.dart';
import 'pages/file_manager_page.dart';
import 'widgets/rename_prefix_dialog.dart'; // Import RenamePrefixDialog
import 'widgets/env_variables_dialog.dart'; // Add import for environment variables dialog
import 'pages/game_library_page.dart';
import 'pages/game_details_page.dart'; // Add import for GameDetailsPage
import 'widgets/about_screen.dart'; // Correct import for AboutScreen

// Constants
// const String appTitle = 'Wine Prefix Manager'; // Removed

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

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
          // Inject PrefixManagementService into UIActionService if needed later
          prefixManagementService: Provider.of<PrefixManagementService>(context, listen: false),
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
    _logService.log('IGDB Client ID Set: ${_settings.igdbClientId.isNotEmpty}');
    _logService.log('IGDB Client Secret Set: ${_settings.igdbClientSecret.isNotEmpty}');
    _logService.log('IGDB Image Base URL: ${_settings.igdbImageBaseUrl}');
    _logService.log('Twitch OAuth URL: ${_settings.twitchOAuthUrl}');
    _logService.log('IGDB API Base URL: ${_settings.igdbApiBaseUrl}');
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
              case '/settings':
                return MaterialPageRoute(builder: (context) => const SettingsPage());
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
          routes: {
            '/manage_prefixes': (context) => ManagePrefixesPage(
              settings: _settings,
              onAddExecutable: (prefix) async {
                // Implementation needed
              },
              onShowCommonComponents: (context, prefix) async {
                // Implementation needed
              },
              onDeletePrefix: (context, prefix) {
                // Implementation needed
              },
              onDeleteExecutable: (context, prefix, exe) {
                // Implementation needed
              },
              onRunExe: (prefix, exe) async {
                // Implementation needed
              },
              onKillProcess: (prefix, exe) async {
                // Implementation needed
              },
              runningProcesses: {},
              onRunWinetricksGui: (prefix) async {
                // Implementation needed
              },
              onRunInstaller: (prefix) async {
                // Implementation needed
              },
              onExploreHostFiles: (prefix) async {
                // Implementation needed
              },
              onRunWinecfg: (context, prefix) async {
                // Implementation needed
              },
              onRenamePrefix: (context, prefix, newName) async {
                // Implementation needed
              },
              onApplyControllerFix: (context, prefix) async {
                // Implementation needed
              },
              onEditEnvVariables: (context, prefix) async {
                // Implementation needed
              },
            ),
            '/game_library': (context) => GameLibraryPage(
              games: [], // Provide empty list for now
              onLaunchGame: (prefix, exe) async {}, // Default empty function
              onSaveLaunchOptions: (game, options) async {}, // Default empty function
              onChangeCategory: (game, category) async {}, // Default empty function
              onToggleWorkingStatus: (game, notWorking) async {}, // Default empty function
              gameLaunchStates: {}, // Default empty map
              onStopGame: (game) {}, // Default empty function
            ),
            '/logs': (context) => LogsPage(),
            '/file_manager': (context) => FileManagerPage(game: null),
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
  
  // Global key to access navigator
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  
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
              if (mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Prefix renamed to "$newName"')),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Error renaming prefix: $e'), backgroundColor: Theme.of(ctx).colorScheme.error),
                );
              }
            }
          },
          onApplyControllerFix: (ctx, pfx) async {
            try {
              await prefixManagementService.applyControllerFix(pfx, onStatusUpdate: (status) {
                logService.log('Controller Fix: $status');
              });
              if (mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Controller fixes applied to "${pfx.name}"')),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Error applying controller fixes: $e'), backgroundColor: Theme.of(ctx).colorScheme.error),
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error running ${exe.name}: $e')),
              );
            }
          },
          onKillProcess: (pfx, exe) async {
            final pid = _runningProcesses[exe.path];
            if (pid != null) {
              final success = await processService.killProcess(pid);
              if (success) {
                logService.log('Kill signal sent to ${exe.name} (PID: $pid)');
              } else {
                logService.log('Failed to send kill signal to ${exe.name} (PID: $pid)', LogLevel.error);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to kill process for ${exe.name}')),
                );
              }
            } else {
               logService.log('Process for ${exe.name} not found in running list.', LogLevel.warning);
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
        );
      case 2:
        // SettingsPage uses SettingsProvider, no need to pass settings
        return SettingsPage(); 
      case 3:
        return LogsPage();
      case 4:
        return _buildFileManagerPage(context);
      case 5:
        // About page (uses WelcomeScreen widget for now)
        return const AboutScreen();
      default:
        // Adjust default to reflect removed item, or ensure all valid indices are handled.
        // If _selectedIndex can go beyond 4, this needs a valid default.
        return HomePage(onNavigateToTab: navigateToTab); // Default to HomePage
    }
  }

  Widget _buildFileManagerPage(BuildContext context) {
    final prefixProvider = Provider.of<PrefixProvider>(context, listen: false);
    // Use getAllGamesFromPrefixes() directly
    final allGames = prefixProvider.getAllGamesFromPrefixes();
    
    // Even if no games are available, we still want to show the FileManagerPage
    // to allow users to see any in-progress backup operations
    return FileManagerPage(game: allGames.isNotEmpty ? allGames.first : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final selectedColor = isDarkMode ? theme.colorScheme.primary : theme.colorScheme.onPrimary;
    final unselectedColor = isDarkMode ? theme.colorScheme.onSurface.withOpacity(0.7) : theme.colorScheme.onSurface.withOpacity(0.6);
    final railBackgroundColor = theme.colorScheme.surface;

    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: theme.colorScheme.background,
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
                  indicatorColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
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
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.article_outlined),
                      selectedIcon: Icon(Icons.article),
                      label: Text('Logs'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.folder_copy_outlined),
                      selectedIcon: Icon(Icons.folder_copy),
                      label: Text('Files'),
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
