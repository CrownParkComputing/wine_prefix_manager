import 'package:flutter/foundation.dart';

import '../services/log_service.dart';

void logDebug(String message) {
  _log(message, LogLevel.debug);
}

void logInfo(String message) {
  _log(message, LogLevel.info);
}

void logWarning(String message) {
  _log(message, LogLevel.warning);
}

void logError(String message, [Object? error, StackTrace? stackTrace]) {
  final buffer = StringBuffer(message);
  if (error != null) {
    buffer.write(' | error: $error');
  }
  if (stackTrace != null) {
    buffer.write('\n$stackTrace');
  }
  _log(buffer.toString(), LogLevel.error);
}

void _log(String message, LogLevel level) {
  if (kDebugMode) {
    debugPrint('[${level.name.toUpperCase()}] $message');
  }

  try {
    LogService().log(message, level);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[LOGGER][FALLBACK] Failed to write using LogService: $e');
    }
  }
}
