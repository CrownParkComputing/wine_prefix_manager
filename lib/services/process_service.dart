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

class ProcessService {
  /// Runs an executable within a specified Wine/Proton prefix.
  /// 
  /// Monitors the process and calls callbacks on start and exit.
  /// Returns the started Process object, or null if startup fails.
  Future<Process?> runExecutable(
    WinePrefix prefix,
    ExeEntry exe, {
    required ProcessStartCallback onProcessStart,
    required ProcessExitCallback onProcessExit,
  }) async {
    try {
      final baseEnv = {
        'WINEPREFIX': prefix.path,
        'PATH': '${prefix.wineBuildPath}/bin:${Platform.environment['PATH']}', // Ensure existing PATH is included
        'LD_LIBRARY_PATH': '${prefix.wineBuildPath}/lib:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}', // Handle null LD_LIBRARY_PATH
        'GST_PLUGIN_SYSTEM_PATH_1_0': '', // May need adjustment based on build
        'WINEDLLOVERRIDES': 'winemenubuilder.exe=d',
      };

      if (prefix.type == PrefixType.proton) {
        baseEnv['STEAM_COMPAT_CLIENT_INSTALL_PATH'] = prefix.path; // Check if this is correct, might need Steam path
        baseEnv['STEAM_COMPAT_DATA_PATH'] = prefix.path;
      }

      final exeDir = path.dirname(exe.path);
      // Combine baseEnv with existing environment, ensuring baseEnv takes precedence if keys conflict
      final fullEnv = {...Platform.environment, ...baseEnv}; 

      Process process;
      List<String> errors = [];
      String command;
      List<String> arguments;

      // For Proton, we need to handle paths differently
      // The buildPath in prefix settings points to where the Proton runtime is located
      // NOT the prefix directory itself
      String? protonRuntimePath;
      
      if (prefix.type == PrefixType.proton && prefix.wineBuildPath != null) {
        final buildPath = prefix.wineBuildPath!;
        String resolvedPath;
        
        if (path.isAbsolute(buildPath)) {
          resolvedPath = buildPath;
        } else {
          resolvedPath = path.join(Directory.current.path, buildPath);
        }
        
        print('Checking proton build directory: $resolvedPath');
        try {
          final dir = Directory(resolvedPath);
          if (await dir.exists()) {
            final files = await dir.list().toList();
            print('Files in proton directory:');
            for (var file in files) {
              print(' - ${path.basename(file.path)}');
            }
            
            // Find the proton executable - it might be named differently
            String? protonExecutable;
            for (var file in files) {
              if (file is File) {
                if (path.basename(file.path).toLowerCase().contains('proton') || 
                    path.basename(file.path) == 'proton') {
                  protonExecutable = file.path;
                  print('Found potential proton executable: $protonExecutable');
                  break;
                }
              }
            }
            
            if (protonExecutable != null) {
              command = protonExecutable;
            } else {
              // Fall back to the standard path
              command = path.join(resolvedPath, 'proton');
              print('No proton executable found, using default path: $command');
            }
          } else {
            print('ERROR: Proton build directory does not exist: $resolvedPath');
            onProcessExit(exe.path, -1, ['ERROR: Proton build directory does not exist: $resolvedPath']);
            return null;
          }
        } catch (e) {
          print('Error listing proton directory: $e');
          onProcessExit(exe.path, -1, ['Error listing proton directory: $e']);
          return null;
        }
        
        arguments = ['run', exe.path];
      } else {
        // Handle Wine case
        final normalizedBuildPath = path.normalize(
          path.isAbsolute(prefix.wineBuildPath ?? '') 
              ? (prefix.wineBuildPath ?? '') 
              : path.join(Directory.current.path, prefix.wineBuildPath ?? '')
        );
        command = path.join(normalizedBuildPath, 'bin', 'wine');
        arguments = [exe.path];
      }

      print('Running command: $command ${arguments.join(' ')}');
      print('Working directory: $exeDir');
      
      // Make the proton script executable if needed
      if (prefix.type == PrefixType.proton) {
        try {
          await Process.run('chmod', ['+x', command]);
          print('Made proton script executable: $command');
        } catch (e) {
          print('Warning: Could not set executable permission: $e');
        }
      }

      process = await Process.start(
        command,
        arguments,
        workingDirectory: exeDir,
        environment: fullEnv,
        // Always run with runInShell for consistent behavior
        runInShell: true,
      );

      // Notify caller about process start
      onProcessStart(exe.path, process.pid);

      // Asynchronously listen for stderr and exit code
      process.stderr.transform(utf8.decoder).listen((data) {
        print('stderr: $data'); // Log stderr
        errors.add(data);
      });

      // Also capture stdout for debugging
      process.stdout.transform(utf8.decoder).listen((data) {
        print('stdout: $data');
      });

      // Don't await exit code here, let the caller manage the process lifetime
      process.exitCode.then((exitCode) {
        print('${exe.name} exited with code $exitCode');
        onProcessExit(exe.path, exitCode, errors);
      });

      return process;

    } catch (e) {
      print('Error running ${exe.name}: $e');
      // Immediately call the exit callback with an error code (e.g., -1)
      onProcessExit(exe.path, -1, ['Error starting process: $e']);
      return null;
    }
  }

  /// Kills a process by its PID.
  /// Returns true if the kill command was issued successfully, false otherwise.
  Future<bool> killProcess(int pid) async {
    try {
      // Use 'kill' command, might need 'taskkill' on Windows
      final shell = Shell(); 
      print('Attempting to kill PID: $pid');
      // Consider using SIGTERM first, then SIGKILL if needed
      await shell.run('kill $pid'); 
      print('Kill command issued for PID: $pid');
      return true;
    } catch (e) {
      print('Error killing process PID $pid: $e');
      return false;
    }
  }
}