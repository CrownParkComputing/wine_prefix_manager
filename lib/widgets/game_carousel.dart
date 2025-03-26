import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import '../widgets/game_card.dart';

class GameCarousel extends StatelessWidget {
  final List<GameEntry> games;
  final Function(GameEntry) onGameTap;
  final Function(BuildContext, GameEntry) onShowDetails;
  final Function(GameEntry) onLaunch;

  const GameCarousel({
    Key? key,
    required this.games,
    required this.onGameTap,
    required this.onShowDetails,
    required this.onLaunch,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text('No games found'),
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: games.length,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final game = games[index];
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: 140,
              child: InkWell(
                onTap: () => onShowDetails(context, game),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: GameCard(
                        game: game,
                        onTap: onGameTap,
                        onLaunch: onLaunch,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      game.exe.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      game.prefix.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
