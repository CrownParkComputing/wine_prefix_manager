import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart'; // Import Provider
import '../models/prefix_models.dart'; // Import the prefix models
import '../providers/prefix_provider.dart'; // Import the PrefixProvider
// import '../services/wine_component_installer.dart'; // Not directly used here
// import 'prefix_management_page.dart'; // Not directly used here
// import '../providers/window_control_provider.dart'; // No longer needed here
import 'game_library_page.dart'; // Import GameLibraryPage
import '../widgets/game_card.dart'; // Import GameCard for GameLaunchState
import '../services/ui_action_service.dart'; // Import UIActionService
import '../services/process_service.dart'; // Import ProcessService for stop logic
import '../services/log_service.dart'; // Import LogService

class HomePage extends StatefulWidget {
  const HomePage({
    Key? key,
  }) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WindowListener {
  String? _selectedGenre; // State for filtering
  // State map to track running games: Key = exePath, Value = PID
  final Map<String, int> _runningGamePids = {};
  // State map to track launch state: Key = exePath, Value = GameLaunchState
  final Map<String, GameLaunchState> _gameLaunchStates = {};

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Any other init logic...
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    // Any other dispose logic...
    super.dispose();
  }

  // --- Game Launch/Stop Callbacks ---
  void _onGameProcessStart(String exePath, int pid) {
    if (mounted) {
      setState(() {
        _runningGamePids[exePath] = pid;
        _gameLaunchStates[exePath] = GameLaunchState.running;
      });
    }
  }

  void _onGameProcessExit(String exePath, int exitCode, List<String> errors) {
     if (mounted) {
       setState(() {
         _runningGamePids.remove(exePath);
         _gameLaunchStates[exePath] = GameLaunchState.idle; // Reset state on exit
       });
     }
     // Logging is handled within UIActionService/ProcessService
  }

  Future<void> _launchGame(BuildContext context, GameEntry entry) async {
    if (_runningGamePids.containsKey(entry.exe.path)) {
      // Already running, maybe bring to front? (Not implemented)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${entry.exe.name} is already running.')),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _gameLaunchStates[entry.exe.path] = GameLaunchState.launching;
      });
    }

    final uiActionService = Provider.of<UIActionService>(context, listen: false);
    // Use the specific callbacks for game state updates
    await uiActionService.launchGame(entry,
      onProcessStart: _onGameProcessStart,
      onProcessExit: _onGameProcessExit,
    );

    // If launchGame throws an error before starting the process, reset state
    if (mounted && _gameLaunchStates[entry.exe.path] == GameLaunchState.launching && !_runningGamePids.containsKey(entry.exe.path)) {
       setState(() {
          _gameLaunchStates[entry.exe.path] = GameLaunchState.idle;
       });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to launch ${entry.exe.name}. Check logs.')),
        );
    }
  }

  Future<void> _stopGame(BuildContext context, GameEntry entry) async {
    final pid = _runningGamePids[entry.exe.path];
    if (pid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${entry.exe.name} is not running.')),
      );
      // Ensure state is idle if PID is missing
      if (mounted && _gameLaunchStates[entry.exe.path] != GameLaunchState.idle) {
         setState(() {
           _gameLaunchStates[entry.exe.path] = GameLaunchState.idle;
         });
      }
      return;
    }

    final processService = Provider.of<ProcessService>(context, listen: false);
    final logService = Provider.of<LogService>(context, listen: false);
    final success = await processService.killProcess(pid);

    if (success) {
      logService.log('Kill signal sent to ${entry.exe.name} (PID: $pid)');
      // State update will happen via _onGameProcessExit callback
    } else {
      logService.log('Failed to send kill signal to ${entry.exe.name} (PID: $pid)', LogLevel.error);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to stop ${entry.exe.name}')),
        );
      }
    }
  }
  // --- End Game Launch/Stop Callbacks ---


  // --- Helper to build GameEntry list ---
  List<GameEntry> _buildGameEntries(List<WinePrefix> prefixes) {
    final List<GameEntry> entries = [];
    for (final prefix in prefixes) {
      for (final exe in prefix.exeEntries) {
        // Optionally filter here if needed (e.g., only show entries marked as 'isGame')
        // if (exe.isGame) {
          entries.add(GameEntry(prefix: prefix, exe: exe));
        // }
      }
    }
    // Optionally sort the combined list
    entries.sort((a, b) => a.exe.name.toLowerCase().compareTo(b.exe.name.toLowerCase()));
    return entries;
  }


  @override
  Widget build(BuildContext context) {
    // Get providers
    final prefixProvider = context.watch<PrefixProvider>();
    final uiActionService = Provider.of<UIActionService>(context, listen: false);
    // final windowControlProvider = Provider.of<WindowControlProvider>(context, listen: false); // No longer needed here

    // Build game list from prefixes
    final allGames = _buildGameEntries(prefixProvider.prefixes);

    return MultiProvider(
      providers: [
        // Make UIActionService available to the GameLibraryPage
        Provider.value(value: uiActionService),
      ],
      child: Scaffold(
        // Removed AppBar
        body: GameLibraryPage(
          games: allGames,
          // Pass the showGameDetails method from UIActionService
          onShowDetails: uiActionService.showGameDetails,
          // Pass the launchGame method defined above
          onLaunchGame: (prefix, exe) {
            _launchGame(context, GameEntry(prefix: prefix, exe: exe));
          },
          // Pass the stopGame method defined above
          onStopGame: (game) {
             _stopGame(context, game);
          },
          gameLaunchStates: _gameLaunchStates, // Pass the actual state map
          selectedGenre: _selectedGenre,
          onGenreSelected: (genre) {
            setState(() {
              _selectedGenre = genre;
            });
          },
          // coverSize: prefixProvider.settings?.coverSize ?? CoverSize.medium, // Get from settings if needed
        ),
      ),
    );
  }
}