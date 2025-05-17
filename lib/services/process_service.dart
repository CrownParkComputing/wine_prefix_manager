import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:process_run/shell.dart';
import '../models/prefix_models.dart'; // Adjust import path as needed

/// Callback type for process exit events.
/// Provides the executable path and the exit code.
typedef ProcessExitCallback = void Function(String exePath, int exitCode, List<String> errors);

/// Callback type for process start events.
/// Provides the executable path and the process ID.
typedef ProcessStartCallback = void Function(String exePath, int pid);

/// Helper function to split arguments respecting quotes (Manual Parser).
List<String> _splitArguments(String argsString) {
  final List<String> result = [];
  final buffer = StringBuffer();
  bool inDoubleQuotes = false;
  bool inSingleQuotes = false;
  bool escaped = false; // Handle potential escape characters if needed (basic for now)

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
  /// Runs an executable within a specified Wine/Proton prefix.
  ///
  /// Monitors the process and calls callbacks on start and exit.
  /// Returns the started Process object, or null if startup fails.
  Future<Process?> runExecutable(
    WinePrefix prefix,
    ExeEntry exe, { // ExeEntry now contains launchOptions and steamAppId
    required ProcessStartCallback onProcessStart,
    required ProcessExitCallback onProcessExit,
  }) async {
    try {
      // Base environment setup
      final baseEnv = {
        'WINEPREFIX': prefix.path,
        // PATH and LD_LIBRARY_PATH are set differently for Proton vs Wine below
      };

      final bool isMsi = exe.path.toLowerCase().endsWith('.msi');
      String command;
      List<String> baseArguments; // Base arguments for wine/proton itself
      String wineExecutablePath; // Path to the wine binary itself
      String wineBinDir; // Directory containing wine binary
      String wineLibDir; // lib directory
      String wineLib64Dir; // lib64 directory

      // --- Determine paths, command, and specific env vars based on prefix type ---

      if (prefix.type == PrefixType.custom) {
        // Custom prefixes use the system's wine installation
        command = 'wine'; // Assume 'wine' is in PATH
        wineExecutablePath = 'wine'; // For potential checks, though existence check might fail if not absolute
        wineBinDir = ''; // Rely on system PATH
        wineLibDir = ''; // Rely on system libs
        wineLib64Dir = ''; // Rely on system libs

        // Base arguments for system wine
        baseArguments = isMsi ? ['wineconsole', 'msiexec', '/i', exe.path] : [exe.path];

      } else if (prefix.type == PrefixType.proton) {
        final buildPath = prefix.wineBuildPath; // Removed unnecessary '!'
         String resolvedPath = path.normalize(path.isAbsolute(buildPath)
            ? buildPath
            : path.join(Directory.current.path, buildPath));
         final protonDir = Directory(resolvedPath);

         if (!await protonDir.exists()) {
           // ERROR: Proton build directory does not exist
           onProcessExit(exe.path, -1, ['ERROR: Proton build directory does not exist: $resolvedPath']);
           return null;
         }

        // Proton structure typically uses 'files/bin', 'files/lib', 'files/lib64'
        // But we need to check different structures for Proton-GE vs other Proton versions
        
        // Check for common directory structures
        bool hasFilesDir = await Directory(path.join(resolvedPath, 'files')).exists();
        bool hasDistDir = await Directory(path.join(resolvedPath, 'dist')).exists();
        
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
          onProcessExit(exe.path, -1, ['ERROR: Could not find wine executable in Proton build: $resolvedPath']);
          return null;
        }
        
        // Once we have the wine path, derive the bin directory
        wineBinDir = path.dirname(wineExecutablePath);

        // Set Proton specific environment variables
        baseEnv['STEAM_COMPAT_CLIENT_INSTALL_PATH'] = Platform.environment['HOME'] ?? '.'; // Use HOME or fallback
        baseEnv['STEAM_COMPAT_DATA_PATH'] = prefix.path;

        if (exe.steamAppId != null && !isMsi) {
          final steamAppIdStr = exe.steamAppId.toString();
          baseEnv['SteamAppId'] = steamAppIdStr;
          baseEnv['SteamGameId'] = steamAppIdStr;
          baseEnv['STEAM_COMPAT_APP_ID'] = steamAppIdStr;
          // Setting Steam App ID for Proton launch
        }
        if (!isMsi) {
           baseEnv['UMU_ID'] = exe.steamAppId?.toString() ?? '1';
           // Setting UMU_ID
        }

        // Determine command for Proton
        if (isMsi) {
          // For MSI with Proton, use internal wine + wineconsole
          if (!await File(wineExecutablePath).exists()) {
              // ERROR: Could not find wine executable within Proton build at expected path
              onProcessExit(exe.path, -1, ['ERROR: Could not find wine executable within Proton build at expected path: $wineExecutablePath']);
              return null;
          }
          command = wineExecutablePath;
          baseArguments = ['wineconsole', 'msiexec', '/i', exe.path];
          try { await Process.run('chmod', ['+x', command]); } catch (e) { /* Warning: Could not set executable permission for internal wine */ }
        } else {
          // For regular executables with Proton, use the 'proton' script
          // Check multiple possible locations for the proton script
          List<String> possibleProtonPaths = [
            path.join(resolvedPath, 'proton'),          // Direct 'proton' script
            path.join(resolvedPath, 'proton_dist', 'bin', 'proton'),  // Some Proton builds
            path.join(resolvedPath, 'files', 'bin', 'proton'),        // Another possible structure
            path.join(resolvedPath, 'dist', 'bin', 'proton')          // Another structure
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
              baseArguments = [exe.path];
              try { 
                await Process.run('chmod', ['+x', command]); 
              } catch (e) { 
                /* Warning: Could not set executable permission for wine */ 
              }
              onProcessExit(exe.path, 0, ['WARNING: Proton script not found, falling back to wine directly']);
            } else {
              // ERROR: Neither Proton script nor wine executable found
              onProcessExit(exe.path, -1, [
                'ERROR: Neither Proton script nor wine executable found in: $resolvedPath',
                'Checked paths: ${possibleProtonPaths.join(", ")}',
                'Also checked wine at: $wineExecutablePath'
              ]);
              return null;
            }
          } else {
            baseArguments = ['run', exe.path]; // Base args for Proton EXE
          }
        }

      } else {
        // Handle standard Wine prefix case (PrefixType.wine)
        final normalizedBuildPath = path.normalize(
          path.isAbsolute(prefix.wineBuildPath) // Removed '?? '''
              ? prefix.wineBuildPath // Removed '?? '''
              : path.join(Directory.current.path, 'wine_builds', prefix.wineBuildPath) // Removed '?? '''
        );
        wineBinDir = path.join(normalizedBuildPath, 'bin');
        wineLibDir = path.join(normalizedBuildPath, 'lib');
        wineLib64Dir = path.join(normalizedBuildPath, 'lib64');
        wineExecutablePath = path.join(wineBinDir, 'wine');

        command = wineExecutablePath;

        if (!await File(command).exists()) {
           // ERROR: Wine executable not found
           onProcessExit(exe.path, -1, ['ERROR: Wine executable not found: $command']);
           return null;
        }

        if (isMsi) {
          baseArguments = ['wineconsole', 'msiexec', '/i', exe.path];
          // Wine MSI mode: using wineconsole
        } else {
          baseArguments = [exe.path];
          // Wine EXE mode
        }
      }

      // --- Start Parsing Launch Options ---
      final Map<String, String> launchEnv = {};
      List<String> wrapperCommands = []; // Commands/args before %command%
      List<String> executableArgs = []; // Args after %command% or all args if no %command%

      if (exe.launchOptions != null && exe.launchOptions!.trim().isNotEmpty) {
        // Parsing launch options
        final optionsString = exe.launchOptions!.trim();
        final commandPlaceholder = '%command%';
        final commandIndex = optionsString.indexOf(commandPlaceholder);

        String beforeCommand = '';
        String afterCommand = '';

        if (commandIndex != -1) {
          beforeCommand = optionsString.substring(0, commandIndex).trim();
          afterCommand = optionsString.substring(commandIndex + commandPlaceholder.length).trim();
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
                launchEnv[kv[0]] = kv[1]; // Env vars can appear after %command% too
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
          ...prefix.environmentVariables, // Include prefix-level environment variables
          ...launchEnv // Launch options override base/platform/prefix env
      };

      // Add DirectX compatibility environment variables by default for Proton and Wine
      // These help with DirectX 12 support
      if (prefix.type == PrefixType.proton) {
        // Default DX12 support for Proton if not overridden
        if (!fullEnv.containsKey('WINEESYNC')) fullEnv['WINEESYNC'] = '1';
        if (!fullEnv.containsKey('WINEFSYNC')) fullEnv['WINEFSYNC'] = '1';
      }

      // Only prepend build paths for non-custom prefixes
      if (prefix.type != PrefixType.custom) {
        fullEnv['PATH'] = '$wineBinDir:${Platform.environment['PATH'] ?? ''}';
        fullEnv['LD_LIBRARY_PATH'] = '$wineLib64Dir:$wineLibDir:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}';
      }


      final exeDir = path.dirname(exe.path);
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


      // Running command
      // Working directory
      // Environment keys

      process = await Process.start(
        finalCommand,
        finalArguments,
        workingDirectory: exeDir,
        environment: fullEnv,
        runInShell: false, // Set to false for better control, true might be needed sometimes
      );

      onProcessStart(exe.path, process.pid);

      process.stderr.transform(utf8.decoder).listen((data) {
        // stderr
        errors.add(data);
      });

      process.stdout.transform(utf8.decoder).listen((data) {
        // stdout
      });

      process.exitCode.then((exitCode) {
        // Exited with code
        onProcessExit(exe.path, exitCode, errors);
      });

      return process;

    } catch (e) { // Removed unused stacktrace variable
      // Error running executable
      // Stacktrace
      onProcessExit(exe.path, -1, ['Error starting process: $e']);
      return null;
    }
  }

  /// Kills a process by its PID.
  Future<bool> killProcess(int pid) async {
    try {
      final shell = Shell();
      // Attempting to kill PID
      await shell.run('kill $pid');
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
}