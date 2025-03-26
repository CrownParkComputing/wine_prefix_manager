import 'package:flutter/material.dart';
import '../models/igdb_models.dart';

class GameSearchDialog extends StatefulWidget {
  final String initialQuery;
  final Future<List<IgdbGame>> Function(String query) onSearch;

  const GameSearchDialog({
    Key? key,
    required this.initialQuery,
    required this.onSearch,
  }) : super(key: key);

  @override
  State<GameSearchDialog> createState() => _GameSearchDialogState();
}

class _GameSearchDialogState extends State<GameSearchDialog> {
  late TextEditingController _controller;
  List<IgdbGame> _results = [];
  bool _isLoading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _search();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_controller.text.isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final results = await widget.onSearch(_controller.text);
      
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error searching: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search Game'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'Game Name',
                      hintText: 'Type game name to search',
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(_error, style: const TextStyle(color: Colors.red)),
              ),
            if (_isLoading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Expanded(
                child: _results.isEmpty
                    ? const Center(child: Text('No results found. Try a different search term.'))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final game = _results[index];
                          return ListTile(
                            title: Text(game.name),
                            subtitle: game.summary != null 
                                ? Text(
                                    game.summary!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(game),
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
