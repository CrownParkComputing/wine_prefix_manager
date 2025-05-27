import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard

class JsonViewerPage extends StatefulWidget {
  final String filePath;

  const JsonViewerPage({Key? key, required this.filePath}) : super(key: key);

  @override
  _JsonViewerPageState createState() => _JsonViewerPageState();
}

class _JsonViewerPageState extends State<JsonViewerPage> {
  String _jsonContent = '';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadJsonContent();
  }

  Future<void> _loadJsonContent() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final file = File(widget.filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        // Pretty print the JSON
        const jsonEncoder = JsonEncoder.withIndent('  ');
        final decodedJson = jsonDecode(content);
        _jsonContent = jsonEncoder.convert(decodedJson);
      } else {
        _error = 'File not found: ${widget.filePath}';
        _jsonContent = ''; // Clear content if file not found
      }
    } catch (e) {
      _error = 'Error reading or parsing JSON file: $e';
      _jsonContent = ''; // Clear content on error
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Game Library JSON Viewer'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8, // 80% of screen width
        height: MediaQuery.of(context).size.height * 0.7, // 70% of screen height
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          onPressed: _loadJsonContent,
                        ),
                      ],
                    ),
                  )
                : _jsonContent.isEmpty && _error == null 
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.info_outline, color: Colors.grey, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              'The file is empty or does not exist at the specified path: ${widget.filePath}',
                              textAlign: TextAlign.center,
                            ),
                             const SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                              onPressed: _loadJsonContent,
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(8.0),
                        child: SelectableText(
                          _jsonContent,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
      ),
      actions: <Widget>[
        if (!_isLoading && _error == null && _jsonContent.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy to Clipboard'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _jsonContent));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('JSON content copied to clipboard')),
              );
            },
          ),
        TextButton(
          child: const Text('Close'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
} 