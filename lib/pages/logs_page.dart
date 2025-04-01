import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        await Share.shareFiles([file.path], text: 'Wine Prefix Manager Logs');
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
  
  @override
  Widget build(BuildContext context) {
    final filteredLogs = _getFilteredLogs();
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title and action buttons
              Row(
                children: [
                  const Text(
                    'Application Logs', 
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
              
              // Filter and search controls
              Row(
                children: [
                  // Level filter
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
                  
                  // Search field
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
        
        // Logs list
        Expanded(
          child: filteredLogs.isEmpty
            ? const Center(
                child: Text('No logs matching the current filters'),
              )
            : ListView.builder(
                itemCount: filteredLogs.length,
                itemBuilder: (context, index) {
                  final log = filteredLogs[index];
                  return _buildLogItem(log);
                },
              ),
        ),
      ],
    );
  }
  
  Widget _buildLogItem(LogEntry log) {
    Color? color;
    Icon? icon;
    
    // Set color and icon based on log level
    switch (log.level) {
      case LogLevel.error:
        color = Colors.red.shade100;
        icon = const Icon(Icons.error_outline, color: Colors.red, size: 18);
        break;
      case LogLevel.warning:
        color = Colors.orange.shade100;
        icon = const Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 18);
        break;
      case LogLevel.info:
        color = null;
        icon = const Icon(Icons.info_outline, color: Colors.blue, size: 18);
        break;
      case LogLevel.debug:
        color = Colors.grey.shade200;
        icon = const Icon(Icons.code, color: Colors.grey, size: 18);
        break;
    }
    
    return Container(
      color: color,
      child: ListTile(
        dense: true,
        leading: icon,
        title: Text(log.message),
        subtitle: Text(
          log.timestamp.toString().split('.')[0],
          style: TextStyle(fontSize: 11),
        ),
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: log.toString()));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Log copied to clipboard')),
          );
        },
      ),
    );
  }
}
