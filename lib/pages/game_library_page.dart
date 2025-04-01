import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart';
import '../widgets/game_card.dart';

class GameLibraryPage extends StatelessWidget {
  final List<GameEntry> games;
  final Function(WinePrefix, ExeEntry) onLaunchGame;
  final Function(BuildContext, GameEntry) onShowDetails;
  final Function(String?)? onGenreSelected;
  final String? selectedGenre;
  final CoverSize coverSize;

  const GameLibraryPage({
    Key? key,
    required this.games,
    required this.onLaunchGame,
    required this.onShowDetails,
    this.onGenreSelected,
    this.selectedGenre,
    this.coverSize = CoverSize.medium,
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
    final filteredGames = selectedGenre != null
        ? games.where((game) => game.exe.category == selectedGenre).toList()
        : games;

    return Column(
      children: [
        // App title - since this is now the main page
        Padding(
          padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0),
          child: Row(
            children: [
              const Text(
                'Game Library',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // Filter button
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filter Games',
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
            child: Row(
              children: [
                const Text('Filtered by: '),
                Chip(
                  label: Text(selectedGenre!),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    if (onGenreSelected != null) onGenreSelected!(null);
                  },
                ),
              ],
            ),
          ),
        // Original Body Content (Expanded)
        Expanded(
          child: filteredGames.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.sports_esports_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        selectedGenre != null 
                            ? 'No games found in category "$selectedGenre"'
                            : 'No games found',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add games in the Manage section',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _getCrossAxisCount(context),
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: filteredGames.length,
                  itemBuilder: (context, index) {
                    final game = filteredGames[index];
                    return GestureDetector(
                      onTap: () => onShowDetails(context, game),
                      child: Card(
                        elevation: 4,
                        clipBehavior: Clip.antiAlias,
                        child: GameCard(
                          game: game,
                          onTap: (g) => onShowDetails(context, g),
                          onLaunch: (g) => onLaunchGame(g.prefix, g.exe),
                          coverSize: coverSize,
                        ),
                      ),
                    );
                  },
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
          title: const Text('Filter Games'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('All Games'),
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
        );
      },
    );
  }
}
