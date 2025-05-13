import 'dart:io'; // Import for File class
import 'package:flutter/material.dart';
import '../models/prefix_models.dart';

// Enum to represent the launch state of a game
// Renamed 'loading' to 'launching' for clarity
enum GameLaunchState { idle, launching, running, failed }

class GameCard extends StatelessWidget {
  final GameEntry game;
  final Function(GameEntry) onTap; // For showing details
  final Function(GameEntry) onLaunch;
  final Function(GameEntry)? onStop; // Callback to stop the game, nullable if not running
  final GameLaunchState launchState; // Current state of the game

  const GameCard({
    Key? key,
    required this.game,
    required this.onTap,
    required this.onLaunch,
    this.onStop,
    this.launchState = GameLaunchState.idle, // Default to idle
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Cover image - Prioritize local file
        (game.exe.localCoverPath != null && game.exe.localCoverPath!.isNotEmpty)
            ? Image.file(
                File(game.exe.localCoverPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildFallbackCover(), // Fallback on file error
              )
            : (game.exe.coverUrl != null && game.exe.coverUrl!.isNotEmpty)
                ? Image.network(
                    game.exe.coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildFallbackCover(), // Fallback on network error
                  )
                : _buildFallbackCover(), // Ultimate fallback

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
                Tooltip(
                  message: 'Marked as not working',
                  child: const Icon(
                    Icons.warning_amber,
                    color: Colors.orange,
                    size: 16,
                  ),
                ),
              // Display play time if available
              if ((game.exe.playTimeMinutes ?? 0) > 0) 
                const SizedBox(width: 8),
              if ((game.exe.playTimeMinutes ?? 0) > 0)
                Tooltip(
                  message: _formatPlayTime(game.exe.playTimeMinutes ?? 0),
                  child: const Icon(
                    Icons.timer,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),

        // Clickable overlay for details
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(game), // Tap anywhere on the card shows details
              splashColor: Colors.white.withOpacity(0.1),
              highlightColor: Colors.white.withOpacity(0.05),
            ),
          ),
        ),

        // Center action button/indicator (Play/Stop/Loading/Error)
        Center(
          child: _buildCenterActionWidget(),
        ),
      ],
    );
  }

  Widget _buildCenterActionWidget() {
    switch (launchState) {
      case GameLaunchState.launching: // Renamed from loading
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          child: const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          ),
        );
      case GameLaunchState.running:
        return IconButton(
          icon: const Icon(
            Icons.stop_circle, // Changed from stop_circle_outline to filled
            color: Colors.redAccent,
            size: 48,
          ),
          tooltip: 'Stop Game',
          // Ensure onStop is called correctly
          onPressed: onStop != null ? () => onStop!(game) : null,
        );
      case GameLaunchState.failed:
        return IconButton(
          icon: const Icon(
            Icons.error_outline,
            color: Colors.orangeAccent,
            size: 48,
          ),
          tooltip: 'Launch Failed (Click to Retry)',
          onPressed: () => onLaunch(game), // Allow retry
        );
      case GameLaunchState.idle:
        // Removed unreachable default case
        return IconButton(
          icon: const Icon(
            Icons.play_circle_outline,
            color: Colors.white70,
            size: 48,
          ),
          tooltip: 'Launch Game',
          onPressed: () => onLaunch(game),
        );
    }
  }


  Widget _buildFallbackCover() {
    return Container(
      color: Colors.grey[800],
      child: Center(
        child: Text(
          game.exe.name.length >= 2
              ? game.exe.name.substring(0, 2).toUpperCase()
              : game.exe.name.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
  
  // Helper method to format play time
  String _formatPlayTime(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return '$hours h ${remainingMinutes > 0 ? '$remainingMinutes m' : ''}';
    }
  }
}
