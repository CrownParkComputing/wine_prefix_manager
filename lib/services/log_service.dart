import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class LogService {
  // Singleton instance
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  // In-memory log storage
  final List<LogEntry> _logs = [];
  
  // Maximum number of logs to keep in memory
  final int maxLogsInMemory = 1000;
  
  // File path for persistent logs
  String? _logFilePath;
  
  // Date formatter for timestamps
  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');
  
  // Initialize log service
  Future<void> initialize() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final logsDir = Directory('${appDir.path}/logs');
      
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }
      
      final now = DateTime.now();
      final dateString = DateFormat('yyyy-MM-dd').format(now);
      _logFilePath = '${logsDir.path}/app_log_$dateString.log';
      
      log('LogService initialized', LogLevel.info);
    } catch (e) {
      debugPrint('Failed to initialize LogService: $e');
    }
  }
  
  // Add a log entry
  void log(String message, [LogLevel level = LogLevel.info]) {
    final timestamp = DateTime.now();
    final entry = LogEntry(
      message: message,
      timestamp: timestamp,
      level: level,
    );
    
    // Add to in-memory logs
    _logs.insert(0, entry); // Add at the beginning (newest first)
    
    // Trim if exceeding max size
    if (_logs.length > maxLogsInMemory) {
      _logs.removeLast();
    }
    
    // Print to console
    debugPrint('${_formatTimestamp(timestamp)} [${level.toString().split('.').last}] $message');
    
    // Write to file asynchronously
    _writeToFile(entry);
  }
  
  // Get all logs
  List<LogEntry> getLogs() {
    return List.unmodifiable(_logs);
  }
  
  // Clear logs
  void clearLogs() {
    _logs.clear();
    log('Logs cleared', LogLevel.info);
  }
  
  // Format timestamp for display
  String _formatTimestamp(DateTime timestamp) {
    return _dateFormatter.format(timestamp);
  }
  
  // Write log entry to file
  Future<void> _writeToFile(LogEntry entry) async {
    if (_logFilePath == null) return;
    
    try {
      final file = File(_logFilePath!);
      final formattedLog = '${_formatTimestamp(entry.timestamp)} [${entry.level.toString().split('.').last}] ${entry.message}\n';
      
      await file.writeAsString(
        formattedLog, 
        mode: FileMode.append,
      );
    } catch (e) {
      debugPrint('Failed to write log to file: $e');
    }
  }
}

// Log entry model
class LogEntry {
  final String message;
  final DateTime timestamp;
  final LogLevel level;
  
  LogEntry({
    required this.message, 
    required this.timestamp, 
    this.level = LogLevel.info
  });
  
  @override
  String toString() {
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    return '${formatter.format(timestamp)} [${level.toString().split('.').last}] $message';
  }
}

// Log levels
enum LogLevel {
  debug,
  info,
  warning,
  error,
}
