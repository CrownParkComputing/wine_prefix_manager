import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/prefix_models.dart';
import '../models/settings.dart';

class GameCard extends StatelessWidget {
  final GameEntry game;
  final Function(GameEntry) onTap;
  final Function(GameEntry) onLaunch;
  final CoverSize coverSize;

  const GameCard({
    Key? key,
    required this.game,
    required this.onTap,
    required this.onLaunch,
    this.coverSize = CoverSize.medium,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Cover image
        game.exe.coverUrl != null
            ? Image.network(
                game.exe.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildFallbackCover(),
              )
            : _buildFallbackCover(),
        
        // Bottom gradient for better text visibility
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 60,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.7),
                ],
              ),
            ),
          ),
        ),
        
        // Icons at the bottom
        Positioned(
          left: 8,
          bottom: 8,
          child: Row(
            children: [
              // Wine/Proton icon
              Icon(
                game.prefix.type == PrefixType.wine ? Icons.wine_bar : Icons.gamepad,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              // Not working warning icon
              if (game.exe.notWorking)
                const Icon(
                  Icons.warning_amber,
                  color: Colors.orange,
                  size: 16,
                ),
            ],
          ),
        ),
        
        // Clickable overlay
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onTap(game),
            child: Center(
              child: IconButton(
                icon: const Icon(
                  Icons.play_circle_outline,
                  color: Colors.white70,
                  size: 48,
                ),
                onPressed: () => onLaunch(game),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackCover() {
    return Container(
      color: Colors.grey[800],
      child: Center(
        child: Text(
          game.exe.name.substring(0, math.min(2, game.exe.name.length)).toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
