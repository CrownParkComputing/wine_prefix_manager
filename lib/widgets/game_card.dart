import 'dart:io'; // Import for File class
import 'package:flutter/material.dart';
import '../models/prefix_models.dart';

// Enum to represent the launch state of a game
// Renamed 'loading' to 'launching' for clarity
enum GameLaunchState { idle, launching, running, failed }

class GameCard extends StatelessWidget {
  final GameEntry game;
  final Function(GameEntry)? onShowInfo; // For showing info modal
  final Function(GameEntry)? onShowSettings; // For showing settings
  final Function(GameEntry) onLaunch;
  final Function(GameEntry)? onStop; // Callback to stop the game, nullable if not running
  final GameLaunchState launchState; // Current state of the game

  const GameCard({
    Key? key,
    required this.game,
    this.onShowInfo, // Changed from onTap
    this.onShowSettings, // Added for settings
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
              if ((game.exe.playTimeMinutes ?? 0) > 0) ...[
                if (game.exe.notWorking) const SizedBox(width: 8),
                Tooltip(
                  message: 'Play time: ${_formatPlayTime(game.exe.playTimeMinutes ?? 0)}',
                  child: const Icon(
                    Icons.timer,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Mini action icons in corners
        // Info icon - top-left
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: IconButton(
              onPressed: () {
                print('Details icon tapped for ${game.exe.name}'); // Debug print
                onShowInfo?.call(game);
              },
              icon: const Icon(
                Icons.info_outline,
                color: Colors.white,
                size: 16,
              ),
              tooltip: 'Game Details',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
            ),
          ),
        ),

        // Settings icon - top-right
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: IconButton(
              onPressed: () {
                print('Settings icon tapped for ${game.exe.name}'); // Debug print
                onShowSettings?.call(game);
              },
              icon: const Icon(
                Icons.settings_outlined,
                color: Colors.white,
                size: 16,
              ),
              tooltip: 'Game Settings',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
            ),
          ),
        ),

        // Clickable overlay for launch (excluding the corner icon areas)
        Positioned(
          left: 40, // Exclude left corner area for info icon
          right: 40, // Exclude right corner area for settings icon
          top: 40, // Exclude top area where icons are
          bottom: 0,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                // This area is for launching the game
                print('Launch area tapped for ${game.exe.name}'); // Debug print
                onLaunch(game);
              },
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
