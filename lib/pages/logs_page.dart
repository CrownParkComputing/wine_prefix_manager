import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/log_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({Key? key}) : super(key: key);

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final LogService _logService = LogService();
  LogLevel _filterLevel = LogLevel.info;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Filter logs based on level and search query
  List<LogEntry> _getFilteredLogs() {
    final allLogs = _logService.getLogs();
    return allLogs.where((log) {
      // Filter by level
      if (log.level.index < _filterLevel.index) {
        return false;
      }

      // Filter by search query
      if (_searchQuery.isEmpty) {
        return true;
      }
      return log.message.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  // Export logs to a file
  Future<void> _exportLogs() async {
    try {
      // Get all logs as text
      final logs = _logService.getLogs();
      final buffer = StringBuffer();
      for (final log in logs) {
        buffer.writeln(log.toString());
      }
      final logsText = buffer.toString();

      if (Platform.isAndroid || Platform.isIOS) {
        // For mobile platforms, use share functionality
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/wine_prefix_manager_logs.txt');
        await file.writeAsString(logsText);
        // Use shareXFiles instead of shareFiles
        await Share.shareXFiles([XFile(file.path)], text: 'Wine Prefix Manager Logs');
      } else {
        // For desktop platforms, save to file
        await FileSaver.instance.saveFile(
          name: 'wine_prefix_manager_logs.txt',
          bytes: Uint8List.fromList(logsText.codeUnits),
          ext: 'txt',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logs exported successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export logs: $e')),
      );
    }
  }

  void _showLogSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Settings'),
        content: const SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Log Management',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text('• Use the filter dropdown to show logs by level'),
              Text('• Use the search box to find specific log entries'),
              Text('• Export logs to save them to a file'),
              Text('• Clear logs to remove all entries'),
              SizedBox(height: 16),
              Text(
                'Log Levels:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Debug: Detailed debugging information'),
              Text('• Info: General information messages'),
              Text('• Warning: Warning messages'),
              Text('• Error: Error messages'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Log Settings',
            onPressed: () => _showLogSettings(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Clear Logs',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Logs'),
                  content: const Text('Are you sure you want to clear all logs?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        _logService.clearLogs();
                        Navigator.pop(context);
                        setState(() {});
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Export Logs',
            onPressed: _exportLogs,
          ),
        ],
      ),
      body: Container(
        color: theme.scaffoldBackgroundColor, // Use scaffold background color
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.save_alt),
                        tooltip: 'Export Logs',
                        onPressed: _exportLogs,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep),
                        tooltip: 'Clear Logs',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Clear Logs'),
                              content: const Text('Are you sure you want to clear all logs?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _logService.clearLogs();
                                    Navigator.pop(context);
                                    setState(() {});
                                  },
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      DropdownButton<LogLevel>(
                        value: _filterLevel,
                        onChanged: (LogLevel? value) {
                          if (value != null) {
                            setState(() {
                              _filterLevel = value;
                            });
                          }
                        },
                        items: LogLevel.values.map((level) {
                          return DropdownMenuItem<LogLevel>(
                            value: level,
                            child: Text(level.toString().split('.').last),
                          );
                        }).toList(),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search logs',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(),
            Expanded(
              child: Builder(
                builder: (context) {
                  final logService = Provider.of<LogService>(context);
                  // Fix: Use getLogs() method instead of the non-existent logEntries getter
                  final logs = logService.getLogs();

                  return logs.isEmpty
                      ? const Center(
                          child: Text('No logs matching the current filters'),
                        )
                      : ListView.builder(
                          itemCount: logs.length,
                          reverse: true,
                          itemBuilder: (context, index) {
                            final log = logs[logs.length - 1 - index];
                            return _buildLogItem(log, theme);
                          },
                        );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(LogEntry log, ThemeData theme) {
    Color textColor;
    switch (log.level) {
      case LogLevel.error:
        textColor = theme.colorScheme.error;
        break;
      case LogLevel.warning:
        textColor = theme.colorScheme.tertiary;
        break;
      default:
        textColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
        color: Colors.transparent, // Ensure log items have transparent background
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${log.timestamp.hour}:${log.timestamp.minute}:${log.timestamp.second}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getLevelColor(log.level, theme).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  log.level.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _getLevelColor(log.level, theme),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            log.message,
            style: TextStyle(color: textColor),
          ),
        ],
      ),
    );
  }

  Color _getLevelColor(LogLevel level, ThemeData theme) {
    switch (level) {
      case LogLevel.error:
        return theme.colorScheme.error;
      case LogLevel.warning:
        return theme.colorScheme.tertiary;
      case LogLevel.info:
        return theme.colorScheme.primary;
      default:
        return theme.textTheme.bodyMedium?.color ?? Colors.white;
    }
  }
}
