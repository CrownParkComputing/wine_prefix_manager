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
  final Function(GameEntry)? onDelete; // Callback to delete the game
  final GameLaunchState launchState; // Current state of the game

  const GameCard({
    Key? key,
    required this.game,
    this.onShowInfo, // Changed from onTap
    this.onShowSettings, // Added for settings
    required this.onLaunch,
    this.onStop,
    this.onDelete, // Add delete callback
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

        // Status indicators at the top-center
        Positioned(
          top: 8,
          left: 50, // Start after info icon area
          right: 50, // End before settings icon area
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Compressed game indicator
                if (game.exe.isCompressed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.archive,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'COMPRESSED',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Not working warning icon
                if (game.exe.notWorking) ...[ 
                  if (game.exe.isCompressed) const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.warning_amber,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ],
                // Display play time if available
                if ((game.exe.playTimeMinutes ?? 0) > 0) ...[
                  if (game.exe.notWorking || game.exe.isCompressed) const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Tooltip(
                      message: 'Play time: ${_formatPlayTime(game.exe.playTimeMinutes ?? 0)}',
                      child: const Icon(
                        Icons.timer,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
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

        // Delete icon - bottom-right
        Positioned(
          bottom: 8,
          right: 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: IconButton(
              onPressed: onDelete != null ? () {
                print('Delete icon tapped for ${game.exe.name}'); // Debug print
                onDelete!(game);
              } : null,
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.white,
                size: 16,
              ),
              tooltip: 'Delete Game',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
            ),
          ),
        ),

        // Play icon - bottom-left (prominent like delete icon)
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            decoration: BoxDecoration(
              color: game.exe.isCompressed 
                  ? Colors.blue.withOpacity(0.8)
                  : Colors.green.withOpacity(0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: IconButton(
              onPressed: () {
                print('Play icon tapped for ${game.exe.name}'); // Debug print
                onLaunch(game);
              },
              icon: Icon(
                launchState == GameLaunchState.running 
                    ? Icons.stop
                    : launchState == GameLaunchState.launching
                        ? Icons.hourglass_bottom
                        : launchState == GameLaunchState.failed
                            ? Icons.error_outline
                            : Icons.play_arrow,
                color: Colors.white,
                size: 16,
              ),
              tooltip: launchState == GameLaunchState.running 
                  ? 'Stop Game'
                  : launchState == GameLaunchState.launching
                      ? 'Launching...'
                      : launchState == GameLaunchState.failed
                          ? 'Launch Failed (Click to Retry)'
                          : game.exe.isCompressed
                              ? 'Extract & Launch Game'
                              : 'Launch Game',
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
          right: 40, // Exclude right corner area for settings icon and delete icon
          top: 40, // Exclude top area where icons are
          bottom: 40, // Exclude bottom area where delete icon is
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
      case GameLaunchState.launching:
        // Show loading indicator when launching
        if (game.exe.isCompressed) {
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.lightBlueAccent),
              ),
            ),
          );
        } else {
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),
          );
        }
      case GameLaunchState.running:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.stop_circle,
            color: Colors.redAccent,
            size: 24,
          ),
        );
      case GameLaunchState.failed:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.error_outline,
            color: Colors.orangeAccent,
            size: 24,
          ),
        );
      case GameLaunchState.idle:
        // Much smaller and subtle central indicator
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.gamepad,
            color: Colors.white.withOpacity(0.3),
            size: 20,
          ),
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
