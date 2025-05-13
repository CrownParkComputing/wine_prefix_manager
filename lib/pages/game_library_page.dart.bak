import 'package:flutter/material.dart';
import 'package:collection/collection.dart'; // Import for groupBy
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../widgets/game_card.dart'; // Import GameCard for GameLaunchState
import '../services/ui_action_service.dart'; // Import UIActionService for addExecutableToPrefix
import 'package:provider/provider.dart'; // Import Provider to access UIActionService

class GameLibraryPage extends StatelessWidget {
  final List<GameEntry> games;
  final Function(WinePrefix, ExeEntry) onLaunchGame;
  final Function(BuildContext, GameEntry) onShowDetails;
  final Function(String?)? onGenreSelected;
  final String? selectedGenre;
  final CoverSize coverSize; // Keep this for potential future use or other widgets
  final Map<String, GameLaunchState> gameLaunchStates; // Add state map
  final Function(GameEntry) onStopGame; // Add stop callback

  const GameLibraryPage({
    Key? key,
    required this.games,
    required this.onLaunchGame,
    required this.onShowDetails,
    this.onGenreSelected,
    this.selectedGenre,
    this.coverSize = CoverSize.medium, // Keep default here
    required this.gameLaunchStates, // Make required
    required this.onStopGame, // Make required
  }) : super(key: key);

  // Get unique categories from all games
  List<String?> get categories {
    final Set<String?> cats = {};

    // Include null category explicitly (for uncategorized games)
    cats.add(null);

    for (final game in games) {
      if (game.exe.category != null) {
        cats.add(game.exe.category);
      }
    }

    // Sort non-null categories
    final sortedCats = cats.where((c) => c != null).toList()..sort();

    // Return null first, followed by sorted categories
    return [null, ...sortedCats];
  }

  @override
  Widget build(BuildContext context) {
    // Apply genre filter first
    final filteredGames = selectedGenre != null
        ? games.where((game) => game.exe.category == selectedGenre).toList()
        : games;

    // Group filtered games by prefix
    final groupedGames = groupBy<GameEntry, WinePrefix>(
      filteredGames,
      (game) => game.prefix,
    );

    // Sort prefixes by name for consistent order
    final sortedPrefixes = groupedGames.keys.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Stack(
      children: [
        Column(
          children: [
            // Header with Filter Button (Title Removed)
            Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0, bottom: 8.0),
              child: Row(
                children: [
                  // Removed Title Text Widget
                  // const Text(
                  //   'Game Library',
                  //   style: TextStyle(
                  //     fontSize: 24,
                  //     fontWeight: FontWeight.bold,
                  //   ),
                  // ),
                  const Spacer(), // Takes up space where title was
                  IconButton(
                    icon: const Icon(Icons.filter_list),
                    tooltip: 'Filter Games by Category',
                    onPressed: () {
                      _showFilterDialog(context);
                    },
                  ),
                ],
              ),
            ),
            // Display current filter if one is selected
            if (selectedGenre != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: Text('Category: ${selectedGenre!}'),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      if (onGenreSelected != null) onGenreSelected!(null);
                    },
                  ),
                ),
              ),
            // Game List Area
            Expanded(
              child: filteredGames.isEmpty
                  ? Center( // Show message if no games match filter or no games exist
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.sports_esports_outlined, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            selectedGenre != null
                                ? 'No games found in category "$selectedGenre"'
                                : 'No games found in library',
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add games via the Manage tab',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder( // Use ListView for prefix groups
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      itemCount: sortedPrefixes.length,
                      itemBuilder: (context, index) {
                        final prefix = sortedPrefixes[index];
                        final gamesInPrefix = groupedGames[prefix]!;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Prefix Header with Add Executable Button
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    prefix.name,
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  // Add EXE button specific to this prefix
                                  IconButton(
                                    icon: const Icon(Icons.add),
                                    tooltip: 'Add Executable to this prefix',
                                    onPressed: () {
                                      // Get the root navigator context
                                      final navigatorContext = Navigator.of(context).context;
                                      _addExecutableToPrefix(navigatorContext, prefix);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            // Grid for games within this prefix
                            GridView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                              shrinkWrap: true, // Important for GridView inside ListView
                              physics: const NeverScrollableScrollPhysics(), // Disable GridView scrolling
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _getCrossAxisCount(context),
                                childAspectRatio: 0.7,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: gamesInPrefix.length,
                              itemBuilder: (context, gameIndex) {
                                final game = gamesInPrefix[gameIndex];
                                // Get the launch state for this specific game
                                final launchState = gameLaunchStates[game.exe.path] ?? GameLaunchState.idle;

                                return Card( // Removed GestureDetector, GameCard handles taps
                                  elevation: 4,
                                  clipBehavior: Clip.antiAlias,
                                  child: GameCard(
                                    game: game,
                                    onTap: (g) => onShowDetails(context, g), // Pass details callback
                                    onLaunch: (g) => onLaunchGame(g.prefix, g.exe), // Pass launch callback
                                    onStop: onStopGame, // Pass stop callback
                                    launchState: launchState, // Pass current state
                                    // Removed coverSize parameter
                                  ),
                                );
                              },
                            ),
                            const Divider(height: 24, thickness: 1, indent: 16, endIndent: 16), // Separator between prefixes
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
        // Global Floating Action Button for adding executables
        Positioned(
          right: 16.0,
          bottom: 16.0,
          child: FloatingActionButton(
            heroTag: 'addExecutable',
            onPressed: () {
              // Get the root navigator context
              final navigatorContext = Navigator.of(context).context;
              _showAddExecutableDialog(navigatorContext, sortedPrefixes);
            },
            tooltip: 'Add Executable to Prefix',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 6;
    if (width > 900) return 5;
    if (width > 600) return 4;
    if (width > 400) return 3;
    return 2;
  }

  void _showFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Filter by Category'),
          content: SizedBox(
            width: 300, // Constrain width
            child: ListView( // Use ListView for potentially long category lists
              shrinkWrap: true,
              children: [
                ListTile(
                  title: const Text('All Categories'),
                  selected: selectedGenre == null,
                  onTap: () {
                    if (onGenreSelected != null) onGenreSelected!(null);
                    Navigator.pop(context);
                  },
                ),
                const Divider(),
                ...categories.map((category) => ListTile(
                      title: Text(category ?? 'Uncategorized'),
                      selected: selectedGenre == category,
                      onTap: () {
                        if (onGenreSelected != null) onGenreSelected!(category);
                        Navigator.pop(context);
                      },
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // Method to show dialog for selecting a prefix to add an executable to
  void _showAddExecutableDialog(BuildContext context, List<WinePrefix> prefixes) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Select a Prefix'),
          content: SizedBox(
            width: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: prefixes.length,
              itemBuilder: (listContext, index) {
                final prefix = prefixes[index];
                return ListTile(
                  title: Text(prefix.name),
                  subtitle: Text(prefix.path),
                  onTap: () {
                    // Close the dialog
                    Navigator.pop(dialogContext);
                    // Use the original passed-in context which should be the root navigator context
                    _addExecutableToPrefix(context, prefix);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
  
  // Method to add executable to a specific prefix - uses the same UIActionService method
  // that's used in the prefix management screen
  void _addExecutableToPrefix(BuildContext context, WinePrefix prefix) {
    // Find uiActionService from the context
    final uiActionService = Provider.of<UIActionService>(context, listen: false);
    
    // Make sure we're using the primary navigator context for dialogs
    final navigatorContext = Navigator.of(context).context;
    
    // Use the navigator's root context for showing dialogs
    uiActionService.addExecutableToPrefix(navigatorContext, prefix);
  }
}
