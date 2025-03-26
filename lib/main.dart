import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'models/wine_build.dart';
import 'models/settings.dart';
import 'models/prefix_models.dart'; // Import only from prefix_models.dart
import 'models/igdb_models.dart';
import 'pages/settings_page.dart';
import 'widgets/game_search_dialog.dart';
import 'widgets/game_card.dart';
import 'widgets/game_details_dialog.dart';
import 'theme/theme_provider.dart';
import 'widgets/game_carousel.dart';
import 'pages/game_library_page.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const WinePrefixManager(),
    ),
  );
}

class WinePrefixManager extends StatelessWidget {
  const WinePrefixManager({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return MaterialApp(
      title: 'Wine Prefix Manager',
      theme: themeProvider.themeData,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<BaseBuild> _builds = [];
  List<WinePrefix> _prefixes = [];
  final Map<String, int> _runningProcesses = {};  // Map exe path to PID
  BaseBuild? _selectedBuild;
  PrefixType _selectedPrefixType = PrefixType.wine;
  PrefixType _selectedPrefixListType = PrefixType.wine;  // For prefix list tab
  bool _isLoading = false;
  String _prefixName = '';
  String _status = '';
  Settings? _settings;
  final TextEditingController _prefixNameController = TextEditingController();
  int _currentTabIndex = 0;
  String? _selectedGenre;
  int _initialTabIndex = 2; // Start with game library view

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadSettings();
    _fetchBuilds();
    _loadPrefixes();
    _scanForPrefixes();
  }

  Future<void> _loadSettings() async {
    _settings = await AppSettings.load();
  }

  Future<void> _fetchBuilds() async {
    setState(() {
      _isLoading = true;
      _status = 'Fetching builds...';
    });

    try {
      // Fetch Wine builds
      final wineResponse = await http.get(Uri.parse(
          'https://api.github.com/repos/Kron4ek/Wine-Builds/releases/tags/10.4'));
      
      List<BaseBuild> builds = [];
      
      if (wineResponse.statusCode == 200) {
        final wineData = json.decode(wineResponse.body);
        final wineAssets = wineData['assets'] as List;
        
        builds.addAll(
          wineAssets
              .where((asset) => asset['name'].toString().endsWith('.tar.xz'))
              .map((asset) => WineBuild.fromGitHubAsset(asset, '10.4'))
              .toList()
        );
      }

      // Fetch Proton builds
      final protonResponse = await http.get(Uri.parse(
          'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases'));
      
      if (protonResponse.statusCode == 200) {
        final List<dynamic> releases = json.decode(protonResponse.body);
        builds.addAll(
          releases
              .take(5) // Only get the latest 5 releases
              .map((release) => ProtonBuild.fromGitHubRelease(release))
              .toList()
        );
      }
      
      setState(() {
        _builds = builds;
        _status = 'Found ${builds.length} builds';
      });
    } catch (e) {
      setState(() {
        _status = 'Error fetching builds: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _scanForPrefixes() async {
    if (_settings == null) return;

    final dir = Directory(_settings!.prefixDirectory);
    if (!await dir.exists()) return;

    try {
      await for (final entry in dir.list()) {
        if (entry is Directory) {
          final prefixName = path.basename(entry.path);
          // Check if this is actually a Wine/Proton prefix by looking for system.reg
          final systemReg = File('${entry.path}/system.reg');
          if (await systemReg.exists()) {
            // Try to find the build path and type
            String? buildPath;
            PrefixType type = PrefixType.wine;
            
            final configFile = File('${entry.path}/.prefix_config');
            if (await configFile.exists()) {
              final config = json.decode(await configFile.readAsString());
              buildPath = config['buildPath'];
              type = config['type'] == 'proton' ? PrefixType.proton : PrefixType.wine;
            }

            // Only add if we don't already have this prefix
            if (!_prefixes.any((p) => p.path == entry.path)) {
              final prefix = WinePrefix(
                name: prefixName,
                path: entry.path,
                wineBuildPath: buildPath ?? '',
                type: type,
                exeEntries: [],
              );
              setState(() {
                _prefixes.add(prefix);
              });
            }
          }
        }
      }
      await _savePrefixes();
    } catch (e) {
      print('Error scanning for prefixes: $e');
    }
  }

  Future<void> _savePrefixes() async {
    final homeDir = Platform.environment['HOME']!;
    final file = File('$homeDir/.wine_prefix_manager.json');
    await file.writeAsString(jsonEncode(_prefixes.map((p) => p.toJson()).toList()));
  }

  Future<void> _loadPrefixes() async {
    try {
      final homeDir = Platform.environment['HOME']!;
      final file = File('$homeDir/.wine_prefix_manager.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> json = jsonDecode(content);
        setState(() {
          _prefixes = json.map((p) => WinePrefix.fromJson(p)).toList();
        });
      }
    } catch (e) {
      print('Error loading prefixes: $e');
    }
  }

  Future<void> _downloadAndCreatePrefix() async {
    if (_settings == null) return;
    
    if (_selectedBuild == null) {
      setState(() {
        _status = 'Please select a build';
      });
      return;
    }

    if (_prefixName.isEmpty) {
      setState(() {
        _status = 'Please enter a prefix name';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Downloading build...';
    });

    try {
      final homeDir = Platform.environment['HOME']!;
      final downloadPath = '$homeDir/${_selectedBuild!.type == PrefixType.wine ? "wine_builds" : "proton_builds"}';
      await Directory(downloadPath).create(recursive: true);

      final fileName = _selectedBuild!.name;
      final filePath = '$downloadPath/$fileName';

      // Download the build if it doesn't exist
      if (!File(filePath).existsSync()) {
        final dio = Dio();
        await dio.download(_selectedBuild!.downloadUrl, filePath,
            onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toStringAsFixed(1);
            setState(() {
              _status = 'Downloading: $progress%';
            });
          }
        });
      }

      setState(() {
        _status = 'Extracting build...';
      });

      // Extract the archive
      final shell = Shell();
      await shell.run('tar -xf "$filePath" -C "$downloadPath"');

      // Get the extracted directory name
      final extractedName = fileName.replaceAll(
        _selectedBuild!.type == PrefixType.wine ? '.tar.xz' : '.tar.gz', 
        ''
      );
      final extractedDir = '$downloadPath/$extractedName';

      setState(() {
        _status = 'Creating prefix...';
      });

      // Create prefix directory, using default folder if set
      String prefixPath;
      if (_settings?.defaultPrefixFolder != null && _settings!.defaultPrefixFolder.isNotEmpty) {
        prefixPath = '${_settings!.defaultPrefixFolder}/$_prefixName';
      } else {
        prefixPath = '${_settings!.prefixDirectory}/$_prefixName';
      }
      await Directory(prefixPath).create(recursive: true);

      // Save the build path and type for this prefix
      final configFile = File('$prefixPath/.prefix_config');
      await configFile.writeAsString(jsonEncode({
        'buildPath': extractedDir,
        'type': _selectedBuild!.type == PrefixType.proton ? 'proton' : 'wine'
      }));

      // Set up environment and create prefix
      final baseEnv = {
        'WINEPREFIX': prefixPath,
        'PATH': '$extractedDir/bin:\$PATH',
        'LD_LIBRARY_PATH': '$extractedDir/lib:\$LD_LIBRARY_PATH',
        'GST_PLUGIN_SYSTEM_PATH_1_0': '',
        'WINEDLLOVERRIDES': 'winemenubuilder.exe=d',
      };

      if (_selectedBuild!.type == PrefixType.proton) {
        baseEnv['STEAM_COMPAT_CLIENT_INSTALL_PATH'] = prefixPath;
        baseEnv['STEAM_COMPAT_DATA_PATH'] = prefixPath;
      }

      final fullEnv = {
        ...Platform.environment,
        ...baseEnv,
      };

      final shell2 = Shell(environment: fullEnv);
      
      // Run setup command
      if (_selectedBuild!.type == PrefixType.wine) {
        await shell2.run('$extractedDir/bin/winecfg');
      } else {
        // Create a dummy script to initialize the prefix
        final dummyScript = '${_settings!.prefixDirectory}/_dummy.bat';
        await File(dummyScript).writeAsString('exit 0');
        await shell2.run('$extractedDir/proton run "$dummyScript"');
        await File(dummyScript).delete();
      }

      // Add prefix to list
      final newPrefix = WinePrefix(
        name: _prefixName,
        path: prefixPath,
        wineBuildPath: extractedDir,
        type: _selectedBuild!.type,
        exeEntries: [],
      );

      setState(() {
        _prefixes.add(newPrefix);
        _status = 'Prefix created successfully!';
        _prefixNameController.clear();
        _prefixName = '';
      });

      await _savePrefixes();
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addExeToPrefix(WinePrefix prefix) async {
    try {
      // Get exe file path
      String? filePath;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe'],
      );

      if (result != null && result.files.single.path != null) {
        filePath = result.files.single.path!;
      } else {
        // Fallback to zenity if file picker didn't work
        try {
          final shell = Shell();
          final zenityResult = await shell.run(
            'zenity --file-selection --title="Select Windows Executable" --file-filter="*.exe"'
          );
          if (zenityResult.outText.isNotEmpty) {
            filePath = zenityResult.outText.trim();
          }
        } catch (e) {
          setState(() {
            _status = 'Error: Please install zenity or try a different file picker';
          });
          return;
        }
      }

      if (filePath == null) return;

      // Ask if this is a game or regular application
      final isGame = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Game or Application?'),
          content: const Text('Is this a game or a regular application?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Application'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Game'),
            ),
          ],
        ),
      );

      if (isGame == null) return; // User cancelled

      ExeEntry exeEntry;
      
      if (isGame && _settings?.igdbClientId?.isNotEmpty == true) {
        // For games, search IGDB
        final filename = path.basenameWithoutExtension(filePath);
        
        // Show search dialog
        final game = await showDialog<IgdbGame>(
          context: context,
          builder: (context) => GameSearchDialog(
            initialQuery: filename,
            onSearch: _searchIgdbGames,
          ),
        );
        
        if (game != null) {
          // User selected a game from IGDB
          setState(() {
            _status = 'Fetching game details...';
            _isLoading = true;
          });
          
          final token = await _getIgdbToken();
          if (token != null) {
            final coverUrl = await _fetchCoverUrl(game.cover, token);
            final screenshotUrls = await _fetchScreenshotUrls(game.screenshots, token);
            final videoIds = await _fetchGameVideoIds(game.id, token);
            
            exeEntry = ExeEntry(
              path: filePath,
              name: game.name,
              igdbId: game.id,
              coverUrl: coverUrl,
              screenshotUrls: screenshotUrls,
              videoIds: videoIds,
              isGame: true,
              description: game.summary, // Include game description
            );
            
            // Log created entry info
            _printExeEntryInfo(exeEntry);
            
            setState(() {
              _isLoading = false;
              _status = 'Game added successfully!';
            });
          } else {
            // Fallback if token couldn't be obtained
            exeEntry = ExeEntry(
              path: filePath,
              name: game.name,
              igdbId: game.id,
              isGame: true,
            );
            setState(() {
              _isLoading = false;
              _status = 'Game added without cover (API token issue)';
            });
          }
        } else {
          // User cancelled game selection, create regular entry
          exeEntry = ExeEntry(
            path: filePath,
            name: path.basename(filePath),
            isGame: false,
          );
        }
      } else {
        // Regular application
        exeEntry = ExeEntry(
          path: filePath,
          name: path.basename(filePath),
          isGame: false,
        );
      }
      
      // Add to prefix
      setState(() {
        final index = _prefixes.indexWhere((p) => p.path == prefix.path);
        if (index != -1) {
          final updatedEntries = List<ExeEntry>.from(prefix.exeEntries)..add(exeEntry);
          _prefixes[index] = WinePrefix(
            name: prefix.name,
            path: prefix.path,
            wineBuildPath: prefix.wineBuildPath,
            type: prefix.type,
            exeEntries: updatedEntries,
          );
        }
      });
      
      await _savePrefixes();
    } catch (e) {
      setState(() {
        _status = 'Error adding executable: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _editExe(WinePrefix prefix, ExeEntry oldExe) async {
    try {
      String? filePath;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe'],
      );

      if (result != null && result.files.single.path != null) {
        filePath = result.files.single.path!;
      } else {
        // Fallback to zenity
        try {
          final shell = Shell();
          final zenityResult = await shell.run(
            'zenity --file-selection --title="Select Windows Executable" --file-filter="*.exe"'
          );
          if (zenityResult.outText.isNotEmpty) {
            filePath = zenityResult.outText.trim();
          }
        } catch (e) {
          setState(() {
            _status = 'Error: Please install zenity or try a different file picker';
          });
          return;
        }
      }

      if (filePath != null) {
        final newExe = ExeEntry(
          path: filePath,
          name: path.basename(filePath),
          igdbId: oldExe.igdbId,
          coverUrl: oldExe.coverUrl,
          screenshotUrls: oldExe.screenshotUrls,
        );

        setState(() {
          final index = _prefixes.indexWhere((p) => p.path == prefix.path);
          if (index != -1) {
            final exeList = List<ExeEntry>.from(prefix.exeEntries);
            final exeIndex = exeList.indexWhere((e) => e.path == oldExe.path);
            if (exeIndex != -1) {
              exeList[exeIndex] = newExe;
              _prefixes[index] = WinePrefix(
                name: prefix.name,
                path: prefix.path,
                wineBuildPath: prefix.wineBuildPath,
                type: prefix.type,
                exeEntries: exeList,
              );
            }
          }
        });

        await _savePrefixes();
      }
    } catch (e) {
      setState(() {
        _status = 'Error editing executable: $e';
      });
    }
  }

  Future<void> _removeExe(WinePrefix prefix, ExeEntry exe) async {
    // If the exe is running, kill it first
    if (_runningProcesses.containsKey(exe.path)) {
      await _killProcess(exe.path);
    }

    setState(() {
      final index = _prefixes.indexWhere((p) => p.path == prefix.path);
      if (index != -1) {
        _prefixes[index] = WinePrefix(
          name: prefix.name,
          path: prefix.path,
          wineBuildPath: prefix.wineBuildPath,
          type: prefix.type,
          exeEntries: prefix.exeEntries.where((e) => e.path != exe.path).toList(),
        );
      }
    });

    await _savePrefixes();
  }

  Future<void> _runExe(WinePrefix prefix, ExeEntry exe) async {
    setState(() {
      _isLoading = true;
      _status = 'Running ${exe.name}...';
    });

    try {
      final baseEnv = {
        'WINEPREFIX': prefix.path,
        'PATH': '${prefix.wineBuildPath}/bin:\$PATH',
        'LD_LIBRARY_PATH': '${prefix.wineBuildPath}/lib:\$LD_LIBRARY_PATH',
        'GST_PLUGIN_SYSTEM_PATH_1_0': '',
        'WINEDLLOVERRIDES': 'winemenubuilder.exe=d',
      };

      if (prefix.type == PrefixType.proton) {
        baseEnv['STEAM_COMPAT_CLIENT_INSTALL_PATH'] = prefix.path;
        baseEnv['STEAM_COMPAT_DATA_PATH'] = prefix.path;
      }

      final exeDir = path.dirname(exe.path);
      final fullEnv = {
        ...Platform.environment,
        ...baseEnv,
      };

      Process process;
      List<String> errors = [];

      if (prefix.type == PrefixType.wine) {
        process = await Process.start(
          '${prefix.wineBuildPath}/bin/wine',
          [exe.path],
          workingDirectory: exeDir,
          environment: fullEnv,
        );
      } else {
        process = await Process.start(
          '${prefix.wineBuildPath}/proton',
          ['run', exe.path],
          workingDirectory: exeDir,
          environment: fullEnv,
        );
      }

      // Capture any error output
      process.stderr.transform(utf8.decoder).listen((data) {
        errors.add(data);
      });

      // Store PID and monitor process
      setState(() {
        _runningProcesses[exe.path] = process.pid;
        _status = 'Running ${exe.name} (PID: ${process.pid})';
      });

      // When process exits, handle any errors and cleanup
      final exitCode = await process.exitCode;
      setState(() {
        _runningProcesses.remove(exe.path);
        if (exitCode != 0 && errors.isNotEmpty) {
          _status = 'Error running ${exe.name}: ${errors.join('\n')}';
        } else {
          _status = '${exe.name} exited with code $exitCode';
        }
      });
    } catch (e) {
      setState(() {
        _status = 'Error running ${exe.name}: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _killProcess(String exePath) async {
    final pid = _runningProcesses[exePath];
    if (pid != null) {
      try {
        final shell = Shell();
        await shell.run('kill $pid');
        setState(() {
          _runningProcesses.remove(exePath);
          _status = 'Process terminated';
        });
      } catch (e) {
        setState(() {
          _status = 'Error killing process: $e';
        });
      }
    }
  }

  void _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          onSettingsChanged: () {
            _initialize();
          },
        ),
      ),
    );
  }

  Future<String?> _getIgdbToken() async {
    if (_settings == null || 
        _settings!.igdbClientId.isEmpty || 
        _settings!.igdbClientSecret.isEmpty) {
      setState(() {
        _status = 'IGDB credentials not set. Configure in Settings.';
      });
      return null;
    }

    // Check if we have a valid token already
    if (_settings!.igdbAccessToken != null && 
        _settings!.igdbTokenExpiry != null &&
        _settings!.igdbTokenExpiry!.isAfter(DateTime.now())) {
      return _settings!.igdbAccessToken;
    }

    try {
      final response = await http.post(
        Uri.parse('https://id.twitch.tv/oauth2/token'),
        body: {
          'client_id': _settings!.igdbClientId,
          'client_secret': _settings!.igdbClientSecret,
          'grant_type': 'client_credentials',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['access_token'];
        final expiresIn = Duration(seconds: data['expires_in']);
        
        // Update settings with new token
        _settings = await AppSettings.updateToken(_settings!, token, expiresIn);
        
        return token;
      } else {
        setState(() {
          _status = 'Failed to get IGDB token: ${response.statusCode} ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error getting IGDB token: $e';
      });
    }
    return null;
  }

  Future<List<IgdbGame>> _searchIgdbGames(String query) async {
    final token = await _getIgdbToken();
    if (token == null) return [];

    try {
      final response = await http.post(
        Uri.parse('https://api.igdb.com/v4/games'),
        headers: {
          'Accept': 'application/json',
          'Client-ID': _settings!.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        body: 'search "$query"; fields name,cover,screenshots,videos,summary; where platforms = (6); limit 20;',
      );

      if (response.statusCode == 200) {
        final List<dynamic> games = json.decode(response.body);
        return games.map((g) => IgdbGame.fromJson(g)).toList();
      } else {
        print('IGDB API error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error searching IGDB: $e');
    }
    return [];
  }

  Future<String?> _fetchCoverUrl(int? coverId, String token) async {
    if (coverId == null) return null;
    
    try {
      final response = await http.post(
        Uri.parse('https://api.igdb.com/v4/covers'),
        headers: {
          'Accept': 'application/json',
          'Client-ID': _settings!.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        body: 'fields image_id; where id = $coverId;',
      );

      if (response.statusCode == 200) {
        final List<dynamic> covers = json.decode(response.body);
        if (covers.isNotEmpty) {
          final imageId = covers[0]['image_id'];
          return 'https://images.igdb.com/igdb/image/upload/t_cover_big/$imageId.jpg';
        }
      }
    } catch (e) {
      print('Error fetching cover: $e');
    }
    return null;
  }

  Future<List<String>> _fetchScreenshotUrls(List<int> screenshotIds, String token) async {
    if (screenshotIds.isEmpty) return [];
    
    try {
      final response = await http.post(
        Uri.parse('https://api.igdb.com/v4/screenshots'),
        headers: {
          'Accept': 'application/json',
          'Client-ID': _settings!.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        body: 'fields image_id; where id = (${screenshotIds.join(",")});',
      );

      if (response.statusCode == 200) {
        final List<dynamic> screenshots = json.decode(response.body);
        return screenshots
          .map((s) => 'https://images.igdb.com/igdb/image/upload/t_screenshot_big/${s["image_id"]}.jpg')
          .toList();
      }
    } catch (e) {
      print('Error fetching screenshots: $e');
    }
    return [];
  }

  Future<List<String>> _fetchGameVideoIds(int gameId, String token) async {
    try {
      // Debug print to track API requests
      print('Fetching videos for game ID: $gameId');
      
      final response = await http.post(
        Uri.parse('https://api.igdb.com/v4/game_videos'),
        headers: {
          'Accept': 'application/json',
          'Client-ID': _settings!.igdbClientId,
          'Authorization': 'Bearer $token',
        },
        body: 'fields video_id,name; where game = $gameId;',
      );

      if (response.statusCode == 200) {
        final List<dynamic> videos = json.decode(response.body);
        
        // Debug print response
        print('Found ${videos.length} videos for game $gameId');
        
        final videoIds = videos.map((v) => v['video_id'].toString()).toList();
        return videoIds;
      } else {
        print('Error fetching videos: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Exception fetching game videos: $e');
    }
    return [];
  }

  // Add this helper method to log video IDs
  void _printExeEntryInfo(ExeEntry entry) {
    print('Game: ${entry.name}');
    print('- IGDB ID: ${entry.igdbId}');
    print('- Has cover: ${entry.coverUrl != null}');
    print('- Screenshots: ${entry.screenshotUrls.length}');
    print('- Videos: ${entry.videoIds.length}');
    print('- Video IDs: ${entry.videoIds}');
  }

  Future<String?> _pickExeFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe'],
      );

      if (result != null && result.files.single.path != null) {
        return result.files.single.path!;
      }

      // Fallback to zenity if file picker didn't work
      try {
        final shell = Shell();
        final zenityResult = await shell.run(
          'zenity --file-selection --title="Select Windows Executable" --file-filter="*.exe"'
        );
        if (zenityResult.outText.isNotEmpty) {
          return zenityResult.outText.trim();
        }
      } catch (e) {
        throw Exception('Please install zenity or try a different file picker');
      }
    } catch (e) {
      throw Exception('Error selecting file: $e');
    }
    return null;
  }

  Future<void> _renamePrefix(WinePrefix prefix) async {
    final controller = TextEditingController(text: prefix.name);
    
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Prefix'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'New Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
    
    if (newName != null && newName.isNotEmpty && newName != prefix.name) {
      setState(() {
        _status = 'Renaming prefix...';
        _isLoading = true;
      });
      
      try {
        // Get parent directory
        final parentDir = Directory(path.dirname(prefix.path));
        
        // Create new directory path
        final newPath = path.join(parentDir.path, newName);
        
        // Check if new directory already exists
        final newDir = Directory(newPath);
        if (await newDir.exists()) {
          setState(() {
            _status = 'Error: Prefix with name "$newName" already exists';
            _isLoading = false;
          });
          return;
        }
        
        // Rename directory
        await Directory(prefix.path).rename(newPath);
        
        // Update prefix in the list
        setState(() {
          final index = _prefixes.indexWhere((p) => p.path == prefix.path);
          if (index != -1) {
            _prefixes[index] = WinePrefix(
              name: newName,
              path: newPath,
              wineBuildPath: _prefixes[index].wineBuildPath,
              type: _prefixes[index].type,
              exeEntries: _prefixes[index].exeEntries,
            );
          }
        });
        
        // Save updated prefixes
        await _savePrefixes();
        
        setState(() {
          _status = 'Prefix renamed successfully!';
          _isLoading = false;
        });
      } catch (e) {
        setState(() {
          _status = 'Error renaming prefix folder: $e';
          _isLoading = false;
        });
      }
    }
  }

  // Add method to edit game details
  Future<void> _editGameDetails(GameEntry gameEntry) async {
    // Show dialog with game search option
    final filename = path.basenameWithoutExtension(gameEntry.exe.path);
    
    final game = await showDialog<IgdbGame>(
      context: context,
      builder: (context) => GameSearchDialog(
        initialQuery: filename,
        onSearch: _searchIgdbGames,
      ),
    );
    
    if (game != null) {
      setState(() {
        _status = 'Updating game details...';
        _isLoading = true;
      });
      
      final token = await _getIgdbToken();
      if (token != null) {
        final coverUrl = await _fetchCoverUrl(game.cover, token);
        final screenshotUrls = await _fetchScreenshotUrls(game.screenshots, token);
        final videoIds = await _fetchGameVideoIds(game.id, token);
        
        final updatedExe = ExeEntry(
          path: gameEntry.exe.path,
          name: game.name,
          igdbId: game.id,
          coverUrl: coverUrl,
          screenshotUrls: screenshotUrls,
          videoIds: videoIds,
          isGame: true,
          description: game.summary,  // Add game description
        );
        
        // Update the exe entry in the prefix
        final prefixIndex = _prefixes.indexWhere((p) => p.path == gameEntry.prefix.path);
        if (prefixIndex != -1) {
          final exeList = List<ExeEntry>.from(_prefixes[prefixIndex].exeEntries);
          final exeIndex = exeList.indexWhere((e) => e.path == gameEntry.exe.path);
          
          if (exeIndex != -1) {
            exeList[exeIndex] = updatedExe;
            _prefixes[prefixIndex] = WinePrefix(
              name: _prefixes[prefixIndex].name,
              path: _prefixes[prefixIndex].path,
              wineBuildPath: _prefixes[prefixIndex].wineBuildPath,
              type: _prefixes[prefixIndex].type,
              exeEntries: exeList,
            );
            
            await _savePrefixes();
            setState(() {
              _status = 'Game details updated successfully!';
            });
          }
        }
      }
      
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Add method to change assigned prefix
  Future<void> _changeGamePrefix(GameEntry gameEntry) async {
    // Get list of prefixes as options
    final prefixOptions = _prefixes.where((p) => p.path != gameEntry.prefix.path).toList();
    
    if (prefixOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other prefixes available to move to')),
      );
      return;
    }
    
    final selectedPrefix = await showDialog<WinePrefix>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select New Prefix'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: ListView.builder(
            itemCount: prefixOptions.length,
            itemBuilder: (context, index) {
              final prefix = prefixOptions[index];
              return ListTile(
                leading: Icon(
                  prefix.type == PrefixType.wine ? Icons.wine_bar : Icons.gamepad,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(prefix.name),
                subtitle: Text('Type: ${prefix.type.toString().split('.').last}'),
                onTap: () => Navigator.pop(context, prefix),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    
    if (selectedPrefix != null) {
      setState(() {
        _status = 'Moving game to different prefix...';
        _isLoading = true;
      });
      
      try {
        // Create a copy of the executable entry to add to the new prefix
        final exeCopy = ExeEntry(
          path: gameEntry.exe.path,
          name: gameEntry.exe.name,
          igdbId: gameEntry.exe.igdbId,
          coverUrl: gameEntry.exe.coverUrl,
          screenshotUrls: gameEntry.exe.screenshotUrls,
          videoIds: gameEntry.exe.videoIds,
          isGame: gameEntry.exe.isGame,
          description: gameEntry.exe.description,
          notWorking: gameEntry.exe.notWorking,
          category: gameEntry.exe.category,
          wineTypeOverride: gameEntry.exe.wineTypeOverride,
        );
        
        // First, add to new prefix
        final newPrefixIndex = _prefixes.indexWhere((p) => p.path == selectedPrefix.path);
        if (newPrefixIndex != -1) {
          final updatedEntries = List<ExeEntry>.from(_prefixes[newPrefixIndex].exeEntries)
            ..add(exeCopy);
            
          _prefixes[newPrefixIndex] = WinePrefix(
            name: _prefixes[newPrefixIndex].name,
            path: _prefixes[newPrefixIndex].path,
            wineBuildPath: _prefixes[newPrefixIndex].wineBuildPath,
            type: _prefixes[newPrefixIndex].type,
            exeEntries: updatedEntries,
          );
        }
        
        // Then, remove from old prefix
        final oldPrefixIndex = _prefixes.indexWhere((p) => p.path == gameEntry.prefix.path);
        if (oldPrefixIndex != -1) {
          final updatedEntries = _prefixes[oldPrefixIndex].exeEntries
            .where((e) => e.path != gameEntry.exe.path)
            .toList();
            
          _prefixes[oldPrefixIndex] = WinePrefix(
            name: _prefixes[oldPrefixIndex].name,
            path: _prefixes[oldPrefixIndex].path,
            wineBuildPath: _prefixes[oldPrefixIndex].wineBuildPath,
            type: _prefixes[oldPrefixIndex].type,
            exeEntries: updatedEntries,
          );
        }
        
        // Save updated prefixes
        await _savePrefixes();
        
        setState(() {
          _status = 'Game moved to ${selectedPrefix.name} prefix';
          _isLoading = false;
        });
        
        // Notify the user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Game moved to ${selectedPrefix.name} prefix')),
        );
      } catch (e) {
        setState(() {
          _status = 'Error moving game: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: 0,
      child: Scaffold(
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          type: BottomNavigationBarType.fixed,
          onTap: (index) {
            setState(() {
              _currentTabIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.category),
              label: 'Create',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder),
              label: 'Manage',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.games),
              label: 'Library',
            ),
          ],
        ),
        body: IndexedStack(
          index: _currentTabIndex,
          children: [
            _buildWelcomePage(),
            _buildCreatePrefixTab(),
            _buildManagePrefixesTab(),
            _buildGameLibrary(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Wine Prefix Manager',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Settings'),
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildCreatePrefixTab() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Prefix'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Prefix Type',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<PrefixType>(
                        segments: const [
                          ButtonSegment<PrefixType>(
                            value: PrefixType.wine,
                            label: Text('Wine'),
                            icon: Icon(Icons.wine_bar),
                          ),
                          ButtonSegment<PrefixType>(
                            value: PrefixType.proton,
                            label: Text('Proton'),
                            icon: Icon(Icons.games),
                          ),
                        ],
                        selected: {_selectedPrefixType},
                        onSelectionChanged: (Set<PrefixType> newSelection) {
                          setState(() {
                            _selectedPrefixType = newSelection.first;
                            _selectedBuild = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Build',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _isLoading 
                        ? const Center(child: CircularProgressIndicator())
                        : _builds.where((build) => build.type == _selectedPrefixType).isEmpty
                          ? Center(
                              child: Column(
                                children: [
                                  const Text('No builds available.'),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    onPressed: _fetchBuilds,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Refresh'),
                                  ),
                                ],
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<BaseBuild>(
                                  value: _selectedBuild,
                                  onChanged: (BaseBuild? newValue) {
                                    setState(() {
                                      _selectedBuild = newValue;
                                    });
                                  },
                                  hint: const Text('   Select a build'),
                                  isExpanded: true,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  items: _builds
                                      .where((build) => build.type == _selectedPrefixType)
                                      .map((build) {
                                    return DropdownMenuItem<BaseBuild>(
                                      value: build,
                                      child: Text(build.name),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ),
              
              Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Prefix Name',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _prefixNameController,
                        decoration: InputDecoration(
                          hintText: 'Enter a name for the prefix',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.create_new_folder),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _prefixName = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: (_isLoading || _selectedBuild == null || _prefixName.isEmpty) 
                    ? null 
                    : _downloadAndCreatePrefix,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  icon: const Icon(Icons.add_circle),
                  label: const Text(
                    'Create Prefix',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Card(
                    color: _status.contains('Error')
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            _status.contains('Error') ? Icons.error : Icons.info,
                            color: _status.contains('Error')
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _status,
                              style: TextStyle(
                                color: _status.contains('Error')
                                  ? Theme.of(context).colorScheme.onErrorContainer
                                  : Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManagePrefixesTab() {
    final filteredPrefixes = _prefixes
        .where((prefix) => prefix.type == _selectedPrefixListType)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Prefixes'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Filter dropdown
          DropdownButton<PrefixType>(
            value: _selectedPrefixListType,
            onChanged: (PrefixType? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedPrefixListType = newValue;
                });
              }
            },
            items: PrefixType.values.map((type) {
              final label = type == PrefixType.wine ? 'Wine' : 'Proton';
              final icon = type == PrefixType.wine ? Icons.wine_bar : Icons.games;
              
              return DropdownMenuItem<PrefixType>(
                value: type,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(label),
                  ],
                ),
              );
            }).toList(),
            underline: Container(),
            icon: const Icon(Icons.filter_list),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ],
      ),
      body: filteredPrefixes.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.folder_off,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'No ${_selectedPrefixListType.toString().split('.').last} prefixes found',
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _currentTabIndex = 1; // Switch to Create tab
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Create New Prefix'),
                ),
              ],
            ),
          )
        : ListView.builder(
            itemCount: filteredPrefixes.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final prefix = filteredPrefixes[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  leading: Icon(
                    prefix.type == PrefixType.wine ? Icons.wine_bar : Icons.games,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    prefix.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Path: ${prefix.path}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Rename Prefix',
                        onPressed: () => _renamePrefix(prefix),
                      ),
                      const SizedBox(width: 4),
                      Text('${prefix.exeEntries.length}'),
                    ],
                  ),
                  children: [
                    // Executables list
                    ...prefix.exeEntries.map((exe) => ListTile(
                      leading: Icon(
                        exe.isGame ? Icons.sports_esports : Icons.app_shortcut,
                        color: exe.notWorking
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.secondary,
                      ),
                      title: Text(exe.name),
                      subtitle: Text(
                        exe.path,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: _runningProcesses.containsKey(exe.path)
                                ? const Icon(Icons.stop, color: Colors.red)
                                : const Icon(Icons.play_arrow, color: Colors.green),
                            onPressed: () {
                              if (_runningProcesses.containsKey(exe.path)) {
                                _killProcess(exe.path);
                              } else {
                                _runExe(prefix, exe);
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editExe(prefix, exe),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _removeExe(prefix, exe),
                          ),
                        ],
                      ),
                    )),
                    
                    // Add executable button
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton.icon(
                        onPressed: () => _addExeToPrefix(prefix),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Executable'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _currentTabIndex = 1; // Switch to Create tab
          });
        },
        tooltip: 'Create New Prefix',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildGameLibrary() {
    final List<GameEntry> allGames = [];
    for (final prefix in _prefixes) {
      for (final exe in prefix.exeEntries) {
        if (exe.isGame || exe.igdbId != null) {
          allGames.add(GameEntry(prefix: prefix, exe: exe));
        }
      }
    }

    return GameLibraryPage(
      games: allGames,
      onLaunchGame: _launchGame,
      onShowDetails: _showGameDetails,
      onGenreSelected: (genre) {
        setState(() {
          _selectedGenre = genre;
        });
      },
      selectedGenre: _selectedGenre,
      coverSize: _settings?.coverSize ?? CoverSize.medium,
    );
  }

  Future<void> _launchGame(WinePrefix prefix, ExeEntry exe) async {
    await _runExe(prefix, exe);
  }
  
  Future<void> _showGameDetails(BuildContext context, GameEntry game) {
    return showDialog(
      context: context,
      builder: (context) => GameDetailsDialog(
        game: game,
        settings: _settings!,
        availablePrefixes: _prefixes,
        onEditGame: _editGameDetails,
        onChangePrefix: _changeGamePrefix,
        onLaunchGame: () {
          Navigator.pop(context);
          _launchGame(game.prefix, game.exe);
        },
        onToggleWorkingStatus: (gameEntry, notWorking) {
          // Update UI state immediately
          setState(() {
            final index = _prefixes.indexWhere((p) => p.path == gameEntry.prefix.path);
            if (index != -1) {
              final exeList = List<ExeEntry>.from(_prefixes[index].exeEntries);
              final exeIndex = exeList.indexWhere((e) => e.path == gameEntry.exe.path);
              if (exeIndex != -1) {
                exeList[exeIndex] = ExeEntry(
                  path: gameEntry.exe.path,
                  name: gameEntry.exe.name,
                  igdbId: gameEntry.exe.igdbId,
                  coverUrl: gameEntry.exe.coverUrl,
                  screenshotUrls: gameEntry.exe.screenshotUrls,
                  videoIds: gameEntry.exe.videoIds,
                  isGame: gameEntry.exe.isGame,
                  description: gameEntry.exe.description,
                  notWorking: notWorking,
                  category: gameEntry.exe.category,
                );
                _prefixes[index] = WinePrefix(
                  name: _prefixes[index].name,
                  path: _prefixes[index].path,
                  wineBuildPath: _prefixes[index].wineBuildPath,
                  type: _prefixes[index].type,
                  exeEntries: exeList,
                );
              }
            }
          });
          // Save changes asynchronously
          _savePrefixes();
        },
        onChangeCategory: _updateGameCategory,
      ),
    );
  }

  Future<void> _updateGameCategory(GameEntry game, String? category) async {
    final prefixIndex = _prefixes.indexWhere((p) => p.path == game.prefix.path);
    if (prefixIndex != -1) {
      final exeList = List<ExeEntry>.from(_prefixes[prefixIndex].exeEntries);
      final exeIndex = exeList.indexWhere((e) => e.path == game.exe.path);
      
      if (exeIndex != -1) {
        final updatedExe = ExeEntry(
          path: game.exe.path,
          name: game.exe.name,
          igdbId: game.exe.igdbId,
          coverUrl: game.exe.coverUrl,
          screenshotUrls: game.exe.screenshotUrls,
          videoIds: game.exe.videoIds,
          isGame: game.exe.isGame,
          description: game.exe.description,
          notWorking: game.exe.notWorking,
          category: category,
        );
        
        exeList[exeIndex] = updatedExe;
        _prefixes[prefixIndex] = WinePrefix(
          name: _prefixes[prefixIndex].name,
          path: _prefixes[prefixIndex].path,
          wineBuildPath: _prefixes[prefixIndex].wineBuildPath,
          type: _prefixes[prefixIndex].type,
          exeEntries: exeList,
        );
        
        await _savePrefixes();
        setState(() {});
      }
    }
  }
}