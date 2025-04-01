// ...existing code...

import 'package:flutter/material.dart';
import 'package:wine_prefix_manager/models/game.dart';
import 'package:wine_prefix_manager/views/game_details_view.dart';

/// Shows the tabbed game details modal dialog
void showGameDetailsModal(BuildContext context, Game game) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        child: GameDetailsView(game: game),
      ),
    ),
  );
}

// ...existing code...
