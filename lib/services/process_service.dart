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

      if (prefix.type == PrefixType.wine) {
        command = '${prefix.wineBuildPath}/bin/wine';
        arguments = [exe.path];
      } else { // Proton
        command = '${prefix.wineBuildPath}/proton';
        arguments = ['run', exe.path];
      }

      print('Running command: $command ${arguments.join(' ')}');
      print('Working directory: $exeDir');
      // print('Environment: $fullEnv'); // Uncomment for deep debugging

      process = await Process.start(
        command,
        arguments,
        workingDirectory: exeDir,
        environment: fullEnv,
        runInShell: false, // Usually false is better unless you need shell features
      );

      // Notify caller about process start
      onProcessStart(exe.path, process.pid);

      // Asynchronously listen for stderr and exit code
      process.stderr.transform(utf8.decoder).listen((data) {
        print('stderr: $data'); // Log stderr
        errors.add(data);
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