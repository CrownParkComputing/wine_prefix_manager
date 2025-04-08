import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

// Models
import 'models/settings.dart';
import 'models/prefix_models.dart'; // Import Prefix models for callbacks

// Providers
import 'providers/prefix_provider.dart';
import 'providers/window_control_provider.dart';
import 'theme/theme_provider.dart';

// Services
import 'services/prefix_management_service.dart';
import 'services/prefix_creation_service.dart';
import 'services/process_service.dart';
import 'services/log_service.dart';
import 'services/igdb_service.dart'; // Import IgdbService
import 'services/ui_action_service.dart'; // Import UIActionService

// Widgets & Pages
// import 'widgets/custom_title_bar.dart'; // Removed import
import 'pages/home_page.dart';
import 'pages/manage_prefixes_page.dart';
import 'pages/settings_page.dart';
import 'pages/logs_page.dart';
import 'pages/file_manager_page.dart';
import 'widgets/rename_prefix_dialog.dart'; // Import RenamePrefixDialog

// Constants
// const String appTitle = 'Wine Prefix Manager'; // Removed

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Configure window options
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1000, 700),
    minimumSize: Size(800, 600),
    center: true,
    // backgroundColor: Colors.transparent, // Not needed with normal title bar
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal, // Use standard system title bar
    // windowButtonVisibility: false, // Let system handle buttons
  );

  // Show window after options are set
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    // Set the title that appears in the system title bar
    await windowManager.setTitle('Wine Prefix Manager');
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

        // Service Providers (Singletons)
        Provider.value(value: settings), // Provide settings early
        Provider.value(value: logService), // Provide LogService instance
        Provider(create: (_) => PrefixManagementService()),
        Provider(create: (_) => PrefixCreationService()),
        Provider(create: (_) => ProcessService()),
        Provider(create: (_) => IgdbService()),
        // UIActionService depends on several other providers/services
        Provider(create: (context) => UIActionService(
          logService: Provider.of<LogService>(context, listen: false),
          igdbService: Provider.of<IgdbService>(context, listen: false),
          processService: Provider.of<ProcessService>(context, listen: false),
          prefixProvider: Provider.of<PrefixProvider>(context, listen: false), // Inject PrefixProvider
          settings: Provider.of<Settings>(context, listen: false), // Inject Settings
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
    _settings = Provider.of<Settings>(context, listen: false);
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
          // Replace the routes and initialRoute with home: MainScaffold() to use the navigation rail
          home: const MainScaffold(),
          theme: themeProvider.themeData, // Use dynamic theme data
          themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light, // Set mode based on provider state
          debugShowCheckedModeBanner: false,
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
  int _selectedIndex = 0;
  // Removed service/provider instances that are now primarily accessed via UIActionService or directly where needed
  // late final Settings _settings;
  // late final LogService _logService; // Keep if _addLogMessage remains
  // late final IgdbService _igdbService;
  // late final PrefixProvider _prefixProvider;
  late final UIActionService _uiActionService; // Keep UIActionService
  final Map<String, int> _runningProcesses = {}; // State for running processes

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
    // Get Providers here to use in callbacks
    final prefixProvider = Provider.of<PrefixProvider>(context, listen: false);
    final processService = Provider.of<ProcessService>(context, listen: false);
    final prefixManagementService = Provider.of<PrefixManagementService>(context, listen: false);
    final logService = Provider.of<LogService>(context, listen: false); // Get LogService

    // Pass the UIActionService methods down as needed
    switch (index) {
      case 0:
        return const HomePage();
      case 1:
        return ManagePrefixesPage(
           settings: Provider.of<Settings>(context, listen: false),
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
           onRunWinetricksGui: (pfx) async {
              try {
                await prefixManagementService.runWinetricksGui(pfx);
              } catch (e) {
                logService.log('Error running Winetricks GUI for ${pfx.name}: $e', LogLevel.error);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error running Winetricks GUI: $e')),
                );
              }
           },
           onRunInstaller: (pfx) async {
              await _uiActionService.runInstallerInPrefix(context, pfx);
           },
           onExploreHostFiles: (pfx) async {
              try {
                await prefixManagementService.runWineExplorer(pfx);
              } catch (e) {
                 logService.log('Error running Wine Explorer for ${pfx.name}: $e', LogLevel.error);
                 ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(content: Text('Error running Wine Explorer: $e')),
                 );
              }
           },
           onRunWinecfg: (ctx, pfx) async {
             try {
               await prefixManagementService.runWinecfg(pfx);
             } catch (e) {
               logService.log('Error running winecfg for ${pfx.name}: $e', LogLevel.error);
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('Error running winecfg: $e')),
               );
             }
           },
        );
      case 2:
        return const SettingsPage();
      case 3:
        return const LogsPage();
      case 4:
        return _buildFileManagerPage(context);
      default:
        return const Center(child: Text('Unknown Page'));
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
    final railBackgroundColor = theme.colorScheme.surface; // Use surface color

    // Use a GlobalKey for the Scaffold to access ScaffoldMessenger
    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

    return Scaffold(
      key: scaffoldKey, // Assign the key
      backgroundColor: theme.colorScheme.background, // Ensure scaffold background matches theme
      body: Column(
        children: [
          // CustomTitleBar removed
          // const CustomTitleBar(isConnected: true),
          Expanded(
            child: Row(
              children: <Widget>[
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onItemTapped,
                  labelType: NavigationRailLabelType.selected, // Show labels only when selected
                  backgroundColor: railBackgroundColor, // Use surface color
                  indicatorColor: theme.colorScheme.primaryContainer.withOpacity(0.3), // Subtle indicator
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
                      icon: Icon(Icons.archive_outlined),
                      selectedIcon: Icon(Icons.archive),
                      label: Text('Files'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                // This is the main content area
                Expanded(
                  // Pass scaffold context to pages that might need it (e.g., for dialogs)
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
