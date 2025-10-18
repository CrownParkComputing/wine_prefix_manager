import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:process_run/shell.dart';
import '../models/prefix_models.dart'; // Adjust import path as needed
import 'compressed_game_service.dart';
import 'power_management_service.dart';

/// Callback type for process exit events.
/// Provides the executable path and the exit code.
typedef ProcessExitCallback = void Function(
    String exePath, int exitCode, List<String> errors);

/// Callback type for process start events.
/// Provides the executable path and the process ID.
typedef ProcessStartCallback = void Function(String exePath, int pid);

/// Helper function to split arguments respecting quotes (Manual Parser).
List<String> _splitArguments(String argsString) {
  final List<String> result = [];
  final buffer = StringBuffer();
  bool inDoubleQuotes = false;
  bool inSingleQuotes = false;
  bool escaped =
      false; // Handle potential escape characters if needed (basic for now)

  for (int i = 0; i < argsString.length; i++) {
    final char = argsString[i];

    if (escaped) {
      // If the previous character was an escape, add the current char literally
      buffer.write(char);
      escaped = false;
      continue;
    }

    if (char == '\\') {
      // Found an escape character, the next character is literal
      // Note: This is basic escaping, shell rules can be more complex
      escaped = true;
      continue; // Don't add the backslash itself unless escaped (\\)
    }

    if (char == '"' && !inSingleQuotes) {
      inDoubleQuotes = !inDoubleQuotes;
      continue; // Don't add the quote itself to the argument
    }

    if (char == '\'' && !inDoubleQuotes) {
      inSingleQuotes = !inSingleQuotes;
      continue; // Don't add the quote itself to the argument
    }

    if (char == ' ' && !inDoubleQuotes && !inSingleQuotes) {
      // Space outside quotes signifies the end of an argument
      if (buffer.isNotEmpty) {
        result.add(buffer.toString());
        buffer.clear();
      }
    } else {
      // Add character to the current argument buffer
      buffer.write(char);
    }
  }

  // Add the last argument if the buffer isn't empty
  if (buffer.isNotEmpty) {
    result.add(buffer.toString());
  }

  // Handle potential lingering quote issues (e.g., unmatched quotes) - basic cleanup
  if (inDoubleQuotes || inSingleQuotes) {
    // Warning: Unmatched quotes detected in launch options
    // Depending on desired behavior, could throw error or try to recover
  }

  return result;
}

class ProcessService {
  final CompressedGameService? _compressedGameService;
  final PowerManagementService _powerManagementService;

  ProcessService(
      {CompressedGameService? compressedGameService,
      required PowerManagementService powerManagementService})
      : _compressedGameService = compressedGameService,
        _powerManagementService = powerManagementService;

  /// Runs an executable within a specified Wine/Proton prefix.
  ///
  /// Monitors the process and calls callbacks on start and exit.
  /// Returns the started Process object, or null if startup fails.
  Future<Process?> runExecutable(
    WinePrefix prefix,
    ExeEntry exe, {
    // ExeEntry now contains launchOptions and steamAppId
    required ProcessStartCallback onProcessStart,
    required ProcessExitCallback onProcessExit,
  }) async {
    // Handle compressed games first - declare actualExe at method scope
    ExeEntry actualExe = exe;

    try {
      if (exe.isCompressed && _compressedGameService != null) {
        try {
          // Extract the game and get the real executable path
          final extractedExePath =
              await _compressedGameService!.extractGameForLaunch(exe);

          // Create a temporary ExeEntry for the extracted game
          actualExe = exe.copyWith(
            path: extractedExePath,
            isCompressed: false, // Temporarily treat as uncompressed for launch
            lastExtracted: DateTime.now(),
          );

          // Wrap the onProcessExit callback to handle compressed game cleanup
          final originalOnProcessExit = onProcessExit;
          void wrappedOnProcessExit(String exePath, int exitCode, List<String> errors) {
            // Call the original callback first
            originalOnProcessExit(exePath, exitCode, errors);
            // Handle compressed game post-processing asynchronously
            _compressedGameService?.handleGameExit(exe, prefix);
          }

          // Use the wrapped callback
          onProcessExit = wrappedOnProcessExit;
        } catch (e) {
          onProcessExit(exe.path, -1, ['Error extracting compressed game: $e']);
          return null;
        }
      }

      // Continue with normal execution using actualExe
      // Base environment setup
      final baseEnv = {
        'WINEPREFIX': prefix.path,
        // PATH and LD_LIBRARY_PATH are set differently for Proton vs Wine below
      };

      final bool isMsi = actualExe.path.toLowerCase().endsWith('.msi');
      String command;
      List<String> baseArguments; // Base arguments for wine/proton itself
      String wineExecutablePath; // Path to the wine binary itself
      String wineBinDir; // Directory containing wine binary
      String wineLibDir; // lib directory
      String wineLib64Dir; // lib64 directory

      // --- Determine paths, command, and specific env vars based on prefix type ---

      if (prefix.type == PrefixType.proton) {
        final buildPath = prefix.wineBuildPath; // Removed unnecessary '!'

        // Check if we're running from an AppImage
        final currentPath = Directory.current.path;
        final isAppImage = currentPath.startsWith('/tmp/mount_') ||
            Platform.environment.containsKey('APPIMAGE') ||
            Platform.environment.containsKey('APPDIR');

        String basePath;
        if (isAppImage) {
          // Use writable directory for AppImage
          final homeDir = Platform.environment['HOME'];
          if (homeDir != null) {
            basePath =
                path.join(homeDir, '.local', 'share', 'wine_prefix_manager');
          } else {
            basePath = path.join('/tmp', 'wine_prefix_manager');
          }
        } else {
          basePath = Directory.current.path;
        }

        String resolvedPath = path.normalize(path.isAbsolute(buildPath)
            ? buildPath
            : path.join(basePath, buildPath));
        final protonDir = Directory(resolvedPath);

        if (!await protonDir.exists()) {
          // ERROR: Proton build directory does not exist
          onProcessExit(actualExe.path, -1,
              ['ERROR: Proton build directory does not exist: $resolvedPath']);
          return null;
        }

        // Proton structure typically uses 'files/bin', 'files/lib', 'files/lib64'
        // But we need to check different structures for Proton-GE vs other Proton versions

        // Check for common directory structures
        bool hasFilesDir =
            await Directory(path.join(resolvedPath, 'files')).exists();
        bool hasDistDir =
            await Directory(path.join(resolvedPath, 'dist')).exists();

        // Set paths based on detected structure
        if (hasFilesDir) {
          // Proton-GE structure
          wineBinDir = path.join(resolvedPath, 'files', 'bin');
          wineLibDir = path.join(resolvedPath, 'files', 'lib');
          wineLib64Dir = path.join(resolvedPath, 'files', 'lib64');
        } else if (hasDistDir) {
          // Some other Proton structures
          wineBinDir = path.join(resolvedPath, 'dist', 'bin');
          wineLibDir = path.join(resolvedPath, 'dist', 'lib');
          wineLib64Dir = path.join(resolvedPath, 'dist', 'lib64');
        } else {
          // Fallback to check directly in the build directory
          wineBinDir = path.join(resolvedPath, 'bin');
          wineLibDir = path.join(resolvedPath, 'lib');
          wineLib64Dir = path.join(resolvedPath, 'lib64');
        }

        // Check all possible wine executable locations
        List<String> possibleWinePaths = [
          path.join(wineBinDir, 'wine'),
          path.join(resolvedPath, 'files', 'bin', 'wine'),
          path.join(resolvedPath, 'dist', 'bin', 'wine'),
          path.join(resolvedPath, 'bin', 'wine')
        ];

        wineExecutablePath = '';
        for (var winePath in possibleWinePaths) {
          if (await File(winePath).exists()) {
            wineExecutablePath = winePath;
            break;
          }
        }

        if (wineExecutablePath.isEmpty) {
          onProcessExit(actualExe.path, -1, [
            'ERROR: Could not find wine executable in Proton build: $resolvedPath'
          ]);
          return null;
        }

        // Once we have the wine path, derive the bin directory
        wineBinDir = path.dirname(wineExecutablePath);

        // Set Proton specific environment variables
        baseEnv['STEAM_COMPAT_CLIENT_INSTALL_PATH'] =
            Platform.environment['HOME'] ?? '.'; // Use HOME or fallback
        
        // For Proton, STEAM_COMPAT_DATA_PATH should point to the parent directory
        // of the pfx folder, not the pfx folder itself
        String compatDataPath = prefix.path;
        if (prefix.path.endsWith('/pfx') || prefix.path.endsWith('\\pfx')) {
          // Remove the /pfx suffix to get the parent directory
          compatDataPath = path.dirname(prefix.path);
        }
        baseEnv['STEAM_COMPAT_DATA_PATH'] = compatDataPath;
        
        // Set WINEPREFIX to the actual pfx directory for wine commands
        baseEnv['WINEPREFIX'] = prefix.path;

        if (actualExe.steamAppId != null && !isMsi) {
          final steamAppIdStr = actualExe.steamAppId.toString();
          baseEnv['SteamAppId'] = steamAppIdStr;
          baseEnv['SteamGameId'] = steamAppIdStr;
          baseEnv['STEAM_COMPAT_APP_ID'] = steamAppIdStr;
          // Setting Steam App ID for Proton launch
        }
        if (!isMsi) {
          baseEnv['UMU_ID'] = actualExe.steamAppId?.toString() ?? '1';
          // Setting UMU_ID
        }

        // Determine command for Proton
        if (isMsi) {
          // For MSI with Proton, use internal wine + wineconsole
          if (!await File(wineExecutablePath).exists()) {
            // ERROR: Could not find wine executable within Proton build at expected path
            onProcessExit(actualExe.path, -1, [
              'ERROR: Could not find wine executable within Proton build at expected path: $wineExecutablePath'
            ]);
            return null;
          }
          command = wineExecutablePath;
          baseArguments = ['wineconsole', 'msiexec', '/i', actualExe.path];
          try {
            await Process.run('chmod', ['+x', command]);
          } catch (e) {
            /* Warning: Could not set executable permission for internal wine */
          }
        } else {
          // For regular executables with Proton, use the 'proton' script
          // Check multiple possible locations for the proton script
          List<String> possibleProtonPaths = [
            path.join(resolvedPath, 'proton'), // Direct 'proton' script
            path.join(resolvedPath, 'proton_dist', 'bin',
                'proton'), // Some Proton builds
            path.join(resolvedPath, 'files', 'bin',
                'proton'), // Another possible structure
            path.join(
                resolvedPath, 'dist', 'bin', 'proton') // Another structure
          ];

          command = "";
          for (var protonPath in possibleProtonPaths) {
            if (await File(protonPath).exists()) {
              command = protonPath;
              try {
                await Process.run('chmod', ['+x', command]);
              } catch (e) {
                /* Warning: Could not set executable permission for proton script */
              }
              break;
            }
          }

          if (command.isEmpty) {
            // If we can't find the proton script, fall back to using wine directly
            if (await File(wineExecutablePath).exists()) {
              command = wineExecutablePath;
              baseArguments = [actualExe.path];
              try {
                await Process.run('chmod', ['+x', command]);
              } catch (e) {
                /* Warning: Could not set executable permission for wine */
              }
              onProcessExit(actualExe.path, 0, [
                'WARNING: Proton script not found, falling back to wine directly'
              ]);
            } else {
              // ERROR: Neither Proton script nor wine executable found
              onProcessExit(actualExe.path, -1, [
                'ERROR: Neither Proton script nor wine executable found in: $resolvedPath',
                'Checked paths: ${possibleProtonPaths.join(", ")}',
                'Also checked wine at: $wineExecutablePath'
              ]);
              return null;
            }
          } else {
            baseArguments = ['run', actualExe.path]; // Base args for Proton EXE
          }
        }
      } else if (prefix.type == PrefixType.wine &&
          prefix.wineBuildPath.isNotEmpty) {
        // Handle Wine prefix with custom build path

        // Check if we're running from an AppImage
        final currentPath = Directory.current.path;
        final isAppImage = currentPath.startsWith('/tmp/mount_') ||
            Platform.environment.containsKey('APPIMAGE') ||
            Platform.environment.containsKey('APPDIR');

        String basePath;
        if (isAppImage) {
          // Use writable directory for AppImage
          final homeDir = Platform.environment['HOME'];
          if (homeDir != null) {
            basePath =
                path.join(homeDir, '.local', 'share', 'wine_prefix_manager');
          } else {
            basePath = path.join('/tmp', 'wine_prefix_manager');
          }
        } else {
          basePath = Directory.current.path;
        }

        final normalizedBuildPath = path.normalize(
            path.isAbsolute(prefix.wineBuildPath)
                ? prefix.wineBuildPath
                : path.join(basePath, 'wine_builds', prefix.wineBuildPath));
        wineBinDir = path.join(normalizedBuildPath, 'bin');
        wineLibDir = path.join(normalizedBuildPath, 'lib');
        wineLib64Dir = path.join(normalizedBuildPath, 'lib64');
        wineExecutablePath = path.join(wineBinDir, 'wine');

        command = wineExecutablePath;

        if (!await File(command).exists()) {
          // ERROR: Wine executable not found
          onProcessExit(actualExe.path, -1,
              ['ERROR: Wine executable not found: $command']);
          return null;
        }

        if (isMsi) {
          baseArguments = ['wineconsole', 'msiexec', '/i', actualExe.path];
          // Wine MSI mode: using wineconsole
        } else {
          baseArguments = [actualExe.path];
          // Wine EXE mode
        }
      } else {
        // Handle system Wine prefix case (no custom build)
        command = 'wine'; // Assume 'wine' is in PATH
        wineExecutablePath =
            'wine'; // For potential checks, though existence check might fail if not absolute
        wineBinDir = ''; // Rely on system PATH
        wineLibDir = ''; // Rely on system libs
        wineLib64Dir = ''; // Rely on system libs

        // Base arguments for system wine
        baseArguments = isMsi
            ? ['wineconsole', 'msiexec', '/i', actualExe.path]
            : [actualExe.path];
      }

      // --- Start Parsing Launch Options ---
      final Map<String, String> launchEnv = {};
      List<String> wrapperCommands = []; // Commands/args before %command%
      List<String> executableArgs =
          []; // Args after %command% or all args if no %command%

      if (actualExe.launchOptions != null &&
          actualExe.launchOptions!.trim().isNotEmpty) {
        // Parsing launch options
        final optionsString = actualExe.launchOptions!.trim();
        const commandPlaceholder = '%command%';
        final commandIndex = optionsString.indexOf(commandPlaceholder);

        String beforeCommand = '';
        String afterCommand = '';

        if (commandIndex != -1) {
          beforeCommand = optionsString.substring(0, commandIndex).trim();
          afterCommand = optionsString
              .substring(commandIndex + commandPlaceholder.length)
              .trim();
        } else {
          // If no %command%, treat everything as arguments for the executable
          afterCommand = optionsString;
        }

        // Parse parts before %command% (wrapper commands/args and env vars)
        if (beforeCommand.isNotEmpty) {
          final parts = _splitArguments(beforeCommand);
          for (final part in parts) {
            if (part.contains('=')) {
              final kv = part.split('=');
              if (kv.length == 2 && kv[0].isNotEmpty) {
                launchEnv[kv[0]] = kv[1];
                // Found Env Var (before %command%)
              } else {
                // Ignoring malformed env var part (before %command%)
              }
            } else {
              wrapperCommands.add(part);
              // Found Wrapper Command/Arg
            }
          }
        }

        // Parse parts after %command% (executable args and env vars)
        if (afterCommand.isNotEmpty) {
          final parts = _splitArguments(afterCommand);
          for (final part in parts) {
            if (part.contains('=')) {
              final kv = part.split('=');
              if (kv.length == 2 && kv[0].isNotEmpty) {
                launchEnv[kv[0]] =
                    kv[1]; // Env vars can appear after %command% too
                // Found Env Var (after %command%)
              } else {
                // Ignoring malformed env var part (after %command%)
              }
            } else {
              executableArgs.add(part);
              // Found Executable Argument
            }
          }
        }
      }
      // --- End Parsing Launch Options ---

      // Combine environments: Platform -> baseEnv -> prefixEnv -> launchEnv
      // Set PATH and LD_LIBRARY_PATH, potentially modifying based on prefix type
      final fullEnv = {
        ...Platform.environment,
        ...baseEnv,
        'GST_PLUGIN_SYSTEM_PATH_1_0': '', // Often needed
        'WINEDLLOVERRIDES': 'winemenubuilder.exe=d', // Prevent menu building
        ...prefix
            .environmentVariables, // Include prefix-level environment variables
        ...launchEnv // Launch options override base/platform/prefix env
      };

      // Add DirectX compatibility environment variables by default for Proton and Wine
      // These help with DirectX 12 support
      if (prefix.type == PrefixType.proton) {
        // Default DX12 support for Proton if not overridden
        if (!fullEnv.containsKey('WINEESYNC')) fullEnv['WINEESYNC'] = '1';
        if (!fullEnv.containsKey('WINEFSYNC')) fullEnv['WINEFSYNC'] = '1';
      }

      // Set build paths and architecture for prefixes
      if (prefix.type == PrefixType.proton) {
        fullEnv['PATH'] = '$wineBinDir:${Platform.environment['PATH'] ?? ''}';
        fullEnv['LD_LIBRARY_PATH'] =
            '$wineLib64Dir:$wineLibDir:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}';
      } else if (prefix.type == PrefixType.wine &&
          prefix.wineBuildPath.isNotEmpty) {
        // Set environment for Wine prefixes with custom builds
        fullEnv['PATH'] = '$wineBinDir:${Platform.environment['PATH'] ?? ''}';
        fullEnv['LD_LIBRARY_PATH'] =
            '$wineLib64Dir:$wineLibDir:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}';

        // Critical: Set WINEARCH for proper architecture handling
        fullEnv['WINEARCH'] = 'win64';
      }

      final exeDir = path.dirname(actualExe.path);
      Process process;
      List<String> errors = [];

      // --- Construct Final Command and Arguments ---
      String finalCommand;
      List<String> finalArguments;

      if (wrapperCommands.isNotEmpty) {
        // Use the first wrapper command as the main command
        finalCommand = wrapperCommands.first;
        // The rest of the wrapper commands, the original command, base arguments, and executable arguments become the arguments
        finalArguments = [
          ...wrapperCommands.sublist(1), // Remaining wrapper args
          command, // The original wine/proton command
          ...baseArguments, // Original base arguments (like 'run' or 'wineconsole', and the exe path)
          ...executableArgs // Arguments from launch options after %command%
        ];
      } else {
        // No wrapper commands, use the original command
        finalCommand = command;
        // Combine base arguments and executable arguments
        finalArguments = [
          ...baseArguments, // Original base arguments (like 'run' or 'wineconsole', and the exe path)
          ...executableArgs // Arguments from launch options
        ];
      }
      // --- End Construct Final Command and Arguments ---

      // Debug logging for launch process (commented out for production)
      // print('=== WINE LAUNCH DEBUG ===');
      // print('Prefix: ${prefix.name} (${prefix.architecture})');
      // print('Prefix path: ${prefix.path}');
      // print('Wine build path: ${prefix.wineBuildPath}');
      // print('Final command: $finalCommand');
      // print('Final arguments: ${finalArguments.join(' ')}');
      // print('Working directory: $exeDir');
      // print('Key environment variables:');
      // print('  WINEPREFIX: ${fullEnv['WINEPREFIX']}');
      // print('  WINEARCH: ${fullEnv['WINEARCH']}');
      // print('  PATH: ${fullEnv['PATH']}');
      // print('  LD_LIBRARY_PATH: ${fullEnv['LD_LIBRARY_PATH']}');
      // print('========================');

      // Running command
      // Working directory
      // Environment keys

      // Fix for Flutter Linux graphics context issue
      // Launch the process in a way that doesn't interfere with the graphics context
      try {
        process = await Process.start(
          finalCommand,
          finalArguments,
          workingDirectory: exeDir,
          environment: fullEnv,
          runInShell: true, // Use shell to avoid graphics context issues
        );
      } catch (e) {
        // Fallback: try with detached mode
        process = await Process.start(
          'setsid',
          [finalCommand, ...finalArguments],
          workingDirectory: exeDir,
          environment: fullEnv,
          mode: ProcessStartMode.detached,
        );
      }

      onProcessStart(actualExe.path, process.pid);

      // Inhibit sleep when game starts
      await _powerManagementService.inhibitSleep(
          reason: 'Playing ${actualExe.name}');

      process.stderr.transform(utf8.decoder).listen((data) {
        // stderr
        errors.add(data);
      });

      process.stdout.transform(utf8.decoder).listen((data) {
        // stdout
      });

      process.exitCode.then((exitCode) async {
        // Allow sleep when game exits
        await _powerManagementService.allowSleep();

        // Exited with code
        onProcessExit(actualExe.path, exitCode, errors);
      });

      return process;
    } catch (e) {
      // Removed unused stacktrace variable
      // Error running executable
      // Stacktrace
      onProcessExit(exe.path, -1, ['Error starting process: $e']);
      return null;
    }
  }

  /// Kills a process by its PID.
  /// If [force] is true, uses SIGKILL (-9) instead of SIGTERM (-15)
  /// If [killTree] is true, kills the entire process tree including children
  Future<bool> killProcess(int pid, {bool force = false, bool killTree = false}) async {
    try {
      if (killTree) {
        return await killProcessTree(pid, force: force);
      }
      
      final shell = Shell();
      final signal = force ? '-KILL' : '-TERM';
      // Attempting to kill PID with signal
      await shell.run('kill $signal $pid');
      
      // Wait a moment for graceful termination if using SIGTERM
      if (!force) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Kill command issued for PID
      return true;
    } catch (e) {
      try {
        // Check if process still exists before declaring error
        await Process.run('kill', ['-0', pid.toString()]);
        // If the above doesn't throw, the process exists but kill failed
        // Error killing process PID
        return false;
      } catch (e2) {
        // If kill -0 throws, the process is already gone
        // Process PID likely already terminated
        return true;
      }
    }
  }

  /// Kills an entire process tree starting from the given PID.
  /// This is particularly useful for Wine/Proton processes which spawn multiple children.
  Future<bool> killProcessTree(int pid, {bool force = false}) async {
    try {
      final shell = Shell();
      
      // Get all child processes recursively
      final childPids = await _getChildProcesses(pid);
      
      // Kill children first (bottom-up approach)
      for (final childPid in childPids.reversed) {
        try {
          final signal = force ? '-KILL' : '-TERM';
          await shell.run('kill $signal $childPid');
        } catch (e) {
          // Continue killing other children even if one fails
        }
      }
      
      // Finally kill the parent process
      final signal = force ? '-KILL' : '-TERM';
      await shell.run('kill $signal $pid');
      
      // Wait for graceful termination if using SIGTERM
      if (!force) {
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Check if main process still exists, force kill if needed
        try {
          await Process.run('kill', ['-0', pid.toString()]);
          // Process still exists, force kill it
          await shell.run('kill -KILL $pid');
        } catch (e) {
          // Process is gone, success
        }
      }
      
      return true;
    } catch (e) {
      // Error killing process tree
      return false;
    }
  }

  /// Gets all child process IDs for a given parent PID.
  Future<List<int>> _getChildProcesses(int parentPid) async {
    try {
      // Use pgrep to find child processes
      final result = await Process.run('pgrep', ['-P', parentPid.toString()]);
      
      if (result.exitCode != 0) {
        return []; // No children found
      }
      
      final childPids = <int>[];
      final lines = result.stdout.toString().trim().split('\n');
      
      for (final line in lines) {
        if (line.trim().isNotEmpty) {
          final pid = int.tryParse(line.trim());
          if (pid != null) {
            childPids.add(pid);
            // Recursively get grandchildren
            final grandchildren = await _getChildProcesses(pid);
            childPids.addAll(grandchildren);
          }
        }
      }
      
      return childPids;
    } catch (e) {
      // Error finding child processes, return empty list
      return [];
    }
  }

  /// Kills all Wine/Proton processes for a specific prefix.
  /// This is useful when normal process tracking fails.
  Future<bool> killAllWineProcesses(WinePrefix prefix) async {
    try {
      final shell = Shell();
      
      // Kill wineserver for the specific prefix
      try {
        final envShell = Shell(environment: {'WINEPREFIX': prefix.path});
        await envShell.run('wineserver -k');
      } catch (e) {
        // wineserver might not be available or already stopped
      }
      
      // Find and kill wine processes using this prefix
      final result = await Process.run('ps', ['aux']);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        final pidsToKill = <int>[];
        
        for (final line in lines) {
          if (line.contains(prefix.path) && 
              (line.contains('wine') || line.contains('proton'))) {
            final parts = line.trim().split(RegExp(r'\s+'));
            if (parts.length > 1) {
              final pid = int.tryParse(parts[1]);
              if (pid != null) {
                pidsToKill.add(pid);
              }
            }
          }
        }
        
        // Kill found processes
        for (final pid in pidsToKill) {
          try {
            await shell.run('kill -TERM $pid');
          } catch (e) {
            // Continue with other processes
          }
        }
        
        // Wait and force kill remaining processes
        await Future.delayed(const Duration(seconds: 2));
        for (final pid in pidsToKill) {
          try {
            await Process.run('kill', ['-0', pid.toString()]);
            await shell.run('kill -KILL $pid');
          } catch (e) {
            // Process already gone
          }
        }
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }
}
