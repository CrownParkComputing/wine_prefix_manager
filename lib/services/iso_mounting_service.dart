import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:process_run/shell.dart';
import 'package:flutter/foundation.dart'; // Add import for ChangeNotifier
import '../models/prefix_models.dart';
import 'log_service.dart';

/// Represents a mounted ISO
class MountedIso {
  final String isoPath;
  final String mountPoint;
  final String devicePath; // Virtual device path (e.g., /dev/loop0)
  final DateTime mountedAt;
  final WinePrefix prefix;

  const MountedIso({
    required this.isoPath,
    required this.mountPoint,
    required this.devicePath,
    required this.mountedAt,
    required this.prefix,
  });

  Map<String, dynamic> toJson() => {
    'isoPath': isoPath,
    'mountPoint': mountPoint,
    'devicePath': devicePath,
    'mountedAt': mountedAt.toIso8601String(),
    'prefixName': prefix.name,
  };

  factory MountedIso.fromJson(Map<String, dynamic> json, WinePrefix prefix) => MountedIso(
    isoPath: json['isoPath'] as String,
    mountPoint: json['mountPoint'] as String,
    devicePath: json['devicePath'] as String,
    mountedAt: DateTime.parse(json['mountedAt'] as String),
    prefix: prefix,
  );
}

/// Service for managing ISO mounting in Wine prefixes
/// Simulates CD insertion/ejection by mounting ISOs to virtual drives
class IsoMountingService extends ChangeNotifier {
  final LogService _logService = LogService();
  final Map<String, MountedIso> _mountedIsos = {}; // Key: prefix.name

  IsoMountingService() {
    _initializeLogService();
  }

  Future<void> _initializeLogService() async {
    try {
      await _logService.initialize();
    } catch (e) {
      print('Error initializing LogService: $e');
    }
  }

  /// Get currently mounted ISO for a prefix
  MountedIso? getMountedIso(WinePrefix prefix) {
    return _mountedIsos[prefix.name];
  }

  /// Check if a prefix has an ISO mounted
  bool hasIsoMounted(WinePrefix prefix) {
    return _mountedIsos.containsKey(prefix.name);
  }

  /// Get all mounted ISOs
  List<MountedIso> getAllMountedIsos() {
    return _mountedIsos.values.toList();
  }

  /// Check if passwordless sudo is configured for mounting operations
  Future<bool> _checkSudoPasswordlessSetup() async {
    try {
      final shell = Shell();
      // Try to run sudo losetup without a password
      final result = await shell.run('sudo -n losetup --help').timeout(
        const Duration(seconds: 5),
      );
      return result.first.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Mount an ISO file to a Wine prefix, simulating CD insertion
  Future<bool> mountIso({
    required WinePrefix prefix,
    required String isoPath,
    Function(String)? onStatusUpdate,
  }) async {
    try {
      onStatusUpdate?.call('Preparing to mount ISO...');
      _logService.log('Mounting ISO for prefix: ${prefix.name}');

      // Check sudo setup first
      final sudoSetup = await _checkSudoPasswordlessSetup();
      if (!sudoSetup) {
        const warning = 'Warning: Passwordless sudo not configured. Commands may timeout.';
        _logService.log(warning, LogLevel.warning);
        onStatusUpdate?.call(warning);
      }

      // Validate ISO file exists
      if (!await File(isoPath).exists()) {
        final error = 'ISO file not found: $isoPath';
        _logService.log(error, LogLevel.error);
        onStatusUpdate?.call(error);
        return false;
      }

      // Check if prefix already has an ISO mounted
      if (hasIsoMounted(prefix)) {
        onStatusUpdate?.call('Unmounting existing ISO first...');
        await unmountIso(prefix: prefix, onStatusUpdate: onStatusUpdate);
      }

      // Create temporary mount point
      final tempDir = Directory.systemTemp;
      final mountPoint = path.join(tempDir.path, 'wine_iso_${prefix.name}_${DateTime.now().millisecondsSinceEpoch}');
      await Directory(mountPoint).create(recursive: true);

      onStatusUpdate?.call('Creating virtual CD device...');
      _logService.log('Creating mount point: $mountPoint');

      // Set up loop device for the ISO with timeout
      final shell = Shell();
      
      // Find available loop device with timeout
      onStatusUpdate?.call('Finding available loop device...');
      try {
        final losetupResult = await shell.run('sudo losetup -f').timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Sudo command timed out - please ensure you have sudo privileges without password prompt, or run the setup_iso_mounting.sh script to configure passwordless sudo for mounting operations');
          },
        );
        
        if (losetupResult.first.exitCode != 0) {
          final error = 'Failed to find available loop device: ${losetupResult.first.stderr}';
          _logService.log(error, LogLevel.error);
          onStatusUpdate?.call(error);
          await Directory(mountPoint).delete();
          return false;
        }

        final devicePath = losetupResult.first.stdout.toString().trim();
        _logService.log('Using loop device: $devicePath');

        // Attach ISO to loop device with timeout
        onStatusUpdate?.call('Attaching ISO to virtual device...');
        final attachResult = await shell.run('sudo losetup "$devicePath" "$isoPath"').timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Loop device attachment timed out');
          },
        );
        
        if (attachResult.first.exitCode != 0) {
          final error = 'Failed to attach ISO to loop device: ${attachResult.first.stderr}';
          _logService.log(error, LogLevel.error);
          onStatusUpdate?.call(error);
          await Directory(mountPoint).delete();
          return false;
        }

        // Mount the loop device with timeout
        onStatusUpdate?.call('Mounting virtual CD...');
        final mountResult = await shell.run('sudo mount -o ro "$devicePath" "$mountPoint"').timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Mount operation timed out');
          },
        );
        
        if (mountResult.first.exitCode != 0) {
          final error = 'Failed to mount ISO: ${mountResult.first.stderr}';
          _logService.log(error, LogLevel.error);
          onStatusUpdate?.call(error);
          
          // Cleanup: detach loop device
          try {
            await shell.run('sudo losetup -d "$devicePath"').timeout(const Duration(seconds: 5));
          } catch (e) {
            _logService.log('Warning: Failed to cleanup loop device: $e', LogLevel.warning);
          }
          await Directory(mountPoint).delete();
          return false;
        }

        // Create Wine registry entries to simulate CD drive
        onStatusUpdate?.call('Configuring Wine CD drive...');
        await _createWineCdDrive(prefix, mountPoint, onStatusUpdate);

        // Store mounted ISO info
        final mountedIso = MountedIso(
          isoPath: isoPath,
          mountPoint: mountPoint,
          devicePath: devicePath,
          mountedAt: DateTime.now(),
          prefix: prefix,
        );

        _mountedIsos[prefix.name] = mountedIso;

        onStatusUpdate?.call('ISO mounted successfully!');
        _logService.log('ISO mounted successfully for prefix ${prefix.name}: $isoPath -> $mountPoint');
        
        notifyListeners(); // Notify UI of changes
        return true;
        
      } on TimeoutException catch (e) {
        final error = 'Mount operation timed out: ${e.message}\n\nTo fix this:\n1. Run: chmod +x setup_iso_mounting.sh\n2. Run: ./setup_iso_mounting.sh\n3. Restart the app and try again';
        _logService.log(error, LogLevel.error);
        onStatusUpdate?.call(error);
        // Cleanup mount point
        try {
          await Directory(mountPoint).delete();
        } catch (cleanupError) {
          _logService.log('Warning: Failed to cleanup mount point: $cleanupError', LogLevel.warning);
        }
        return false;
      }
    } catch (e) {
      final error = 'Error mounting ISO: $e';
      _logService.log(error, LogLevel.error);
      onStatusUpdate?.call(error);
      return false;
    }
  }

  /// Unmount ISO from a Wine prefix, simulating CD ejection
  Future<bool> unmountIso({
    required WinePrefix prefix,
    Function(String)? onStatusUpdate,
  }) async {
    try {
      final mountedIso = _mountedIsos[prefix.name];
      if (mountedIso == null) {
        onStatusUpdate?.call('No ISO mounted for this prefix');
        return true; // Not an error if nothing is mounted
      }

      onStatusUpdate?.call('Ejecting virtual CD...');
      _logService.log('Unmounting ISO for prefix: ${prefix.name}');

      final shell = Shell();

      // Remove Wine CD drive registry entries first
      onStatusUpdate?.call('Removing Wine CD drive...');
      await _removeWineCdDrive(prefix, onStatusUpdate);

      // Force any processes to release the mount point
      onStatusUpdate?.call('Ensuring mount point is free...');
      try {
        // Try to find and kill any processes using the mount point
        final lsofResult = await shell.run('lsof +D "${mountedIso.mountPoint}" || true').timeout(
          const Duration(seconds: 5),
        );
        if (lsofResult.first.exitCode == 0 && lsofResult.first.stdout.toString().trim().isNotEmpty) {
          _logService.log('Warning: Found processes using mount point, attempting to release...', LogLevel.warning);
          // Wait a bit for processes to finish naturally
          await Future.delayed(const Duration(seconds: 2));
        }
      } catch (e) {
        _logService.log('Warning: Could not check for processes using mount point: $e', LogLevel.warning);
      }

      // Try unmounting with multiple attempts
      onStatusUpdate?.call('Unmounting device...');
      bool unmountSuccess = false;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          final unmountResult = await shell.run('sudo umount "${mountedIso.mountPoint}"').timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Unmount operation timed out on attempt $attempt');
            },
          );
          if (unmountResult.first.exitCode == 0) {
            unmountSuccess = true;
            break;
          } else {
            _logService.log('Unmount attempt $attempt failed: ${unmountResult.first.stderr}', LogLevel.warning);
            if (attempt < 3) {
              await Future.delayed(const Duration(seconds: 2));
            }
          }
        } on TimeoutException catch (e) {
          _logService.log('Unmount attempt $attempt timed out: ${e.message}', LogLevel.warning);
          if (attempt < 3) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }

      if (!unmountSuccess) {
        _logService.log('Warning: All unmount attempts failed, forcing detach of loop device', LogLevel.warning);
      }

      // Try detaching loop device with multiple attempts
      onStatusUpdate?.call('Detaching virtual device...');
      bool detachSuccess = false;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          final detachResult = await shell.run('sudo losetup -d "${mountedIso.devicePath}"').timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Loop device detach timed out on attempt $attempt');
            },
          );
          if (detachResult.first.exitCode == 0) {
            detachSuccess = true;
            break;
          } else {
            _logService.log('Detach attempt $attempt failed: ${detachResult.first.stderr}', LogLevel.warning);
            if (attempt < 3) {
              await Future.delayed(const Duration(seconds: 2));
            }
          }
        } on TimeoutException catch (e) {
          _logService.log('Detach attempt $attempt timed out: ${e.message}', LogLevel.warning);
          if (attempt < 3) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }

      // Clean up mount point
      try {
        if (await Directory(mountedIso.mountPoint).exists()) {
          await Directory(mountedIso.mountPoint).delete();
        }
      } catch (e) {
        _logService.log('Warning: Failed to remove mount point: $e', LogLevel.warning);
      }

      // Remove from mounted ISOs map
      _mountedIsos.remove(prefix.name);

      final statusMessage = unmountSuccess && detachSuccess 
          ? 'ISO ejected successfully!'
          : 'ISO ejected (some cleanup warnings occurred - check logs)';
      
      onStatusUpdate?.call(statusMessage);
      _logService.log('ISO unmounted successfully for prefix: ${prefix.name}');
      
      notifyListeners(); // Notify UI of changes
      return true;
    } catch (e) {
      final error = 'Error unmounting ISO: $e';
      _logService.log(error, LogLevel.error);
      onStatusUpdate?.call(error);
      return false;
    }
  }

  /// Create Wine registry entries for CD drive
  Future<void> _createWineCdDrive(WinePrefix prefix, String mountPoint, Function(String)? onStatusUpdate) async {
    try {
      final env = await _prepareEnvironment(prefix);
      final shell = Shell(environment: env);

      // Determine wine executable
      final wineExec = await _getWineExecutableForPrefix(prefix);
      
      // Initialize wineprefix if needed
      onStatusUpdate?.call('Initializing Wine prefix...');
      try {
        await shell.run('$wineExec wineboot --init').timeout(const Duration(seconds: 30));
      } catch (e) {
        _logService.log('Warning: wineboot failed: $e', LogLevel.warning);
        // Continue anyway, registry might still work
      }
      
      onStatusUpdate?.call('Configuring Wine CD drive registry...');
      
      // Set up D: drive as CD-ROM with better error handling
      final regCommands = [
        // First, try to delete any existing D: drive entries
        '$wineExec reg delete "HKEY_LOCAL_MACHINE\\Software\\Wine\\Drives" /v "d:" /f',
        '$wineExec reg delete "HKEY_CURRENT_USER\\Software\\Wine\\Drives" /v "d:" /f',
        
        // Create new CD-ROM drive entries
        '$wineExec reg add "HKEY_LOCAL_MACHINE\\Software\\Wine\\Drives" /v "d:" /t REG_SZ /d "cdrom" /f',
        '$wineExec reg add "HKEY_CURRENT_USER\\Software\\Wine\\Drives" /v "d:" /t REG_SZ /d "$mountPoint" /f',
      ];

      for (int i = 0; i < regCommands.length; i++) {
        final cmd = regCommands[i];
        try {
          final result = await shell.run(cmd).timeout(const Duration(seconds: 15));
          if (result.first.exitCode != 0) {
            if (i < 2) {
              // Delete commands - it's okay if they fail (key might not exist)
              _logService.log('Registry delete command failed (expected): $cmd', LogLevel.info);
            } else {
              // Add commands - these should succeed
              _logService.log('Warning: Registry add command failed: $cmd, exit code: ${result.first.exitCode}, stderr: ${result.first.stderr}', LogLevel.warning);
            }
          }
        } catch (e) {
          if (i < 2) {
            _logService.log('Registry delete timed out (expected): $cmd', LogLevel.info);
          } else {
            _logService.log('Warning: Registry add command timed out: $cmd, error: $e', LogLevel.warning);
          }
        }
      }

      _logService.log('Wine CD drive configured for prefix: ${prefix.name}');
    } catch (e) {
      _logService.log('Error configuring Wine CD drive: $e', LogLevel.error);
      // Don't throw - mounting can still work without perfect registry setup
    }
  }

  /// Remove Wine registry entries for CD drive
  Future<void> _removeWineCdDrive(WinePrefix prefix, Function(String)? onStatusUpdate) async {
    try {
      final env = await _prepareEnvironment(prefix);
      final shell = Shell(environment: env);

      // Determine wine executable
      final wineExec = await _getWineExecutableForPrefix(prefix);
      
      // Remove D: drive entries
      final regCommands = [
        '$wineExec reg delete "HKEY_LOCAL_MACHINE\\Software\\Wine\\Drives" /v "d:" /f',
        '$wineExec reg delete "HKEY_CURRENT_USER\\Software\\Wine\\Drives" /v "d:" /f',
      ];

      for (final cmd in regCommands) {
        final result = await shell.run(cmd);
        // Don't log warnings for delete operations as the keys might not exist
      }

      _logService.log('Wine CD drive removed for prefix: ${prefix.name}');
    } catch (e) {
      _logService.log('Error removing Wine CD drive: $e', LogLevel.error);
      // Don't throw on cleanup operations
    }
  }

  /// Prepare environment variables for Wine commands
  Future<Map<String, String>> _prepareEnvironment(WinePrefix prefix) async {
    final env = <String, String>{
      ...Platform.environment,
      'WINEPREFIX': prefix.path,
    };

    if (prefix.wineBuildPath.isNotEmpty) {
      if (prefix.type == PrefixType.proton) {
        // For Proton builds, check different possible locations
        final possibleBinPaths = [
          path.join(prefix.wineBuildPath, 'bin'),
          path.join(prefix.wineBuildPath, 'files', 'bin'),
          path.join(prefix.wineBuildPath, 'dist', 'bin'),
        ];

        for (final binPath in possibleBinPaths) {
          if (await Directory(binPath).exists()) {
            env['PATH'] = '$binPath:${env['PATH'] ?? ''}';
            break;
          }
        }
      } else {
        // For Wine builds
        final binPath = path.join(prefix.wineBuildPath, 'bin');
        if (await Directory(binPath).exists()) {
          env['PATH'] = '$binPath:${env['PATH'] ?? ''}';
        }
      }
    }

    return env;
  }

  /// Get the appropriate wine executable for the prefix
  Future<String> _getWineExecutableForPrefix(WinePrefix prefix) async {
    if (prefix.wineBuildPath.isNotEmpty) {
      if (prefix.type == PrefixType.proton) {
        // For Proton, look for wine in various locations
        final possiblePaths = [
          path.join(prefix.wineBuildPath, 'bin', 'wine'),
          path.join(prefix.wineBuildPath, 'files', 'bin', 'wine'),
          path.join(prefix.wineBuildPath, 'dist', 'bin', 'wine'),
        ];

        for (final winePath in possiblePaths) {
          if (await File(winePath).exists()) {
            return winePath;
          }
        }

        // If specific wine not found, try proton with run command
        final protonScript = path.join(prefix.wineBuildPath, 'proton');
        if (await File(protonScript).exists()) {
          return '$protonScript run wine';
        }
      } else {
        // For Wine builds
        final winePath = path.join(prefix.wineBuildPath, 'bin', 'wine');
        if (await File(winePath).exists()) {
          return winePath;
        }
      }
    }

    // Fallback to system wine
    return 'wine';
  }

  /// Cleanup all mounted ISOs (useful for app shutdown)
  Future<void> cleanupAllMountedIsos() async {
    final mountedPrefixes = _mountedIsos.keys.toList();
    for (final prefixName in mountedPrefixes) {
      final mountedIso = _mountedIsos[prefixName];
      if (mountedIso != null) {
        try {
          await unmountIso(prefix: mountedIso.prefix);
        } catch (e) {
          _logService.log('Error cleaning up mounted ISO for $prefixName: $e', LogLevel.error);
        }
      }
    }
  }
} 