import 'package:flutter/material.dart';
import '../models/igdb_models.dart';

class GameSearchDialog extends StatefulWidget {
  final String initialQuery;
  // Update the function signature to expect a Map
  final Future<Map<String, dynamic>> Function(String query) onSearch;

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
      _results = []; // Clear previous results
    });

    // Call the updated onSearch which returns a Map
    final searchResult = await widget.onSearch(_controller.text);

    // Check if the widget is still mounted before calling setState
    if (!mounted) return;

    // Handle the result map
    if (searchResult.containsKey('error')) {
      setState(() {
        _isLoading = false;
        // Display a more user-friendly error message
        _error = 'Search failed: ${searchResult['error']}';
      });
    } else if (searchResult.containsKey('games')) {
      setState(() {
        _results = searchResult['games'] as List<IgdbGame>;
        _isLoading = false;
        if (_results.isEmpty) {
          _error = 'No results found for "${_controller.text}".';
        }
      });
    } else {
      // Handle unexpected map structure
      setState(() {
        _isLoading = false;
        _error = 'Unexpected search result format.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search Game on IGDB'), // Updated title
      content: SizedBox(
        width: double.maxFinite,
        // Consider making height dynamic or larger if needed
        height: MediaQuery.of(context).size.height * 0.6, // Use a portion of screen height
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      labelText: 'Game Name',
                      hintText: 'Type game name to search',
                      // Add clear button
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _controller.clear();
                                setState(() {
                                  _results = [];
                                  _error = '';
                                });
                              },
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _search(),
                    autofocus: true, // Focus on load
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search', // Add tooltip
                  onPressed: _isLoading ? null : _search, // Disable while loading
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Display error prominently if it exists
            if (_error.isNotEmpty && !_isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  _error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            // Show loading indicator or results/no results message
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isNotEmpty
                      ? ListView.builder(
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
                        )
                      // Only show 'No results' if there's no error message already shown
                      : _error.isEmpty
                          ? const Center(child: Text('Enter a search term.'))
                          : const SizedBox.shrink(), // Hide if error is shown
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
