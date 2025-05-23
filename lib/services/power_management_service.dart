import 'dart:io';
import 'log_service.dart';

class PowerManagementService {
  final LogService _logService;
  Process? _inhibitProcess;
  bool _isInhibited = false;
  
  PowerManagementService(this._logService);

  /// Prevents system sleep/logout using systemd-inhibit
  Future<bool> inhibitSleep({String reason = 'Wine Prefix Manager operation'}) async {
    if (_isInhibited) {
      _logService.log('Sleep inhibit already active');
      return true;
    }

    try {
      // Use systemd-inhibit to prevent sleep, shutdown, and idle
      _inhibitProcess = await Process.start('systemd-inhibit', [
        '--what=sleep:shutdown:idle',
        '--who=Wine Prefix Manager',
        '--why=$reason',
        '--mode=block',
        'sleep', 'infinity'
      ]);

      if (_inhibitProcess != null) {
        _isInhibited = true;
        _logService.log('Sleep/logout inhibited: $reason');
        return true;
      }
    } catch (e) {
      // If systemd-inhibit is not available, try alternative methods
      _logService.log('systemd-inhibit not available, trying xset: $e', LogLevel.warning);
      return await _tryXsetInhibit();
    }
    
    return false;
  }

  /// Alternative method using xset to prevent screen sleep
  Future<bool> _tryXsetInhibit() async {
    try {
      // Disable DPMS (Display Power Management Signaling)
      final result = await Process.run('xset', ['s', 'off', '-dpms']);
      if (result.exitCode == 0) {
        _isInhibited = true;
        _logService.log('Screen sleep disabled using xset');
        return true;
      }
    } catch (e) {
      _logService.log('xset command failed: $e', LogLevel.warning);
    }
    return false;
  }

  /// Allows system sleep/logout by stopping the inhibit process
  Future<void> allowSleep() async {
    if (!_isInhibited) {
      _logService.log('Sleep inhibit is not active');
      return;
    }

    try {
      // Stop the systemd-inhibit process
      if (_inhibitProcess != null) {
        _inhibitProcess!.kill();
        await _inhibitProcess!.exitCode;
        _inhibitProcess = null;
        _logService.log('Sleep/logout inhibit removed');
      } else {
        // Re-enable DPMS if we used xset
        await Process.run('xset', ['s', 'on', '+dpms']);
        _logService.log('Screen sleep re-enabled using xset');
      }
      
      _isInhibited = false;
    } catch (e) {
      _logService.log('Error removing sleep inhibit: $e', LogLevel.error);
    }
  }

  /// Check if sleep is currently inhibited
  bool get isInhibited => _isInhibited;

  /// Cleanup - ensure we allow sleep when service is disposed
  Future<void> dispose() async {
    await allowSleep();
  }
} 