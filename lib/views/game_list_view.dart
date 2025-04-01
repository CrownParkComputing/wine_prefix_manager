import 'package:flutter/material.dart';
// ...existing imports...
import 'package:wine_prefix_manager/views/game_details_view.dart';

// ...existing code...

// Add this method where you handle game selection/clicking
void _showGameDetails(BuildContext context, Game game) {
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        child: GameDetailsView(game: game),
      ),ild: Container(
    ),  width: MediaQuery.of(context).size.width * 0.8,
  );    height: MediaQuery.of(context).size.height * 0.8,
}       child: GameDetailsView(game: game),
      ),
// In your build method or item builder, update the onTap handler:
onTap: () {
  print('Game card clicked: ${game.name}');
  Navigator.of(context).push(
    MaterialPageRoute(p handler:
      builder: (context) => GameDetailsView(game: game), () {
    ),vigator.of(context).push(
  );  MaterialPageRoute(
},t) => GameDetailsView(game: game),
// ...existing code...    ),

  );
},
// ...existing code...
