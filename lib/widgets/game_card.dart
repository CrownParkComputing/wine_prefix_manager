import 'dart:io'; // Import for File class
import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart'; // Import for CoverSize enum
import '../utils/logger.dart';

// Enum to represent the launch state of a game
// Renamed 'loading' to 'launching' for clarity
enum GameLaunchState { idle, launching, running, failed }

class GameCard extends StatelessWidget {
  final GameEntry game;
  final CoverSize coverSize; // Add cover size parameter
  final Function(GameEntry)? onShowInfo; // For showing info modal
  final Function(GameEntry)? onShowSettings; // For showing settings
  final Function(GameEntry) onLaunch;
  final Function(GameEntry)?
      onStop; // Callback to stop the game, nullable if not running
  final Function(GameEntry)? onDelete; // Callback to delete the game
  final GameLaunchState launchState; // Current state of the game

  const GameCard({
    super.key,
    required this.game,
    this.coverSize = CoverSize.medium, // Default to medium size
    this.onShowInfo, // Changed from onTap
    this.onShowSettings, // Added for settings
    required this.onLaunch,
    this.onStop,
    this.onDelete, // Add delete callback
    this.launchState = GameLaunchState.idle, // Default to idle
  });

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
                errorBuilder: (_, __, ___) =>
                    _buildFallbackCover(), // Fallback on file error
              )
            : (game.exe.coverUrl != null && game.exe.coverUrl!.isNotEmpty)
                ? Image.network(
                    game.exe.coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _buildFallbackCover(), // Fallback on network error
                  )
                : _buildFallbackCover(), // Ultimate fallback

        // Bottom gradient for better text visibility
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: _getBottomGradientHeight(),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha:0.7),
                ],
              ),
            ),
          ),
        ),

        // Status indicators at the top-center
        Positioned(
          top: _getTopPadding(),
          left: _getIconAreaSize() + 8, // Start after info icon area
          right: _getIconAreaSize() + 8, // End before settings icon area
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Compressed game indicator
                  if (game.exe.isCompressed)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: _getSmallPadding(),
                        vertical: _getSmallPadding() / 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha:0.9),
                        borderRadius: BorderRadius.circular(_getBorderRadius()),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.archive,
                            color: Colors.white,
                            size: _getSmallIconSize(),
                          ),
                          SizedBox(width: _getSmallPadding() / 2),
                          Text(
                            'ZIP',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: _getSmallTextSize(),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Info icon - top-left
        Positioned(
          top: _getTopPadding(),
          left: _getTopPadding(),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha:0.8),
              borderRadius: BorderRadius.circular(_getBorderRadius() + 2),
              border: Border.all(
                color: Colors.white.withValues(alpha:0.3),
                width: 1,
              ),
            ),
            child: IconButton(
              onPressed: () {
                logDebug(
                    'Details icon tapped for ${game.exe.name}'); // Debug print
                onShowInfo?.call(game);
              },
              icon: Icon(
                Icons.info_outline,
                color: Colors.white,
                size: _getCornerIconSize(),
              ),
              tooltip: 'Game Details',
              padding: EdgeInsets.all(_getCornerIconSize() * 0.3),
              constraints: BoxConstraints(
                minWidth: _getCornerIconSize() + 8,
                minHeight: _getCornerIconSize() + 8,
              ),
            ),
          ),
        ),

        // Settings icon - top-right
        Positioned(
          top: _getTopPadding(),
          right: _getTopPadding(),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha:0.8),
              borderRadius: BorderRadius.circular(_getBorderRadius() + 2),
              border: Border.all(
                color: Colors.white.withValues(alpha:0.3),
                width: 1,
              ),
            ),
            child: IconButton(
              onPressed: () {
                logDebug(
                    'Settings icon tapped for ${game.exe.name}'); // Debug print
                onShowSettings?.call(game);
              },
              icon: Icon(
                Icons.settings,
                color: Colors.white,
                size: _getCornerIconSize(),
              ),
              tooltip: 'Game Settings',
              padding: EdgeInsets.all(_getCornerIconSize() * 0.3),
              constraints: BoxConstraints(
                minWidth: _getCornerIconSize() + 8,
                minHeight: _getCornerIconSize() + 8,
              ),
            ),
          ),
        ),

        // Game title text - bottom (avoid overlapping with delete icon)
        Positioned(
          bottom: 0,
          left: 0,
          right: onDelete != null ? _getIconAreaSize() : 0, // Leave space for delete icon if present
          child: Container(
            padding: EdgeInsets.all(_getSmallPadding()),
            child: Text(
              game.exe.name,
              style: TextStyle(
                color: Colors.white,
                fontSize: _getTextSize(),
                fontWeight: FontWeight.bold,
                shadows: const [
                  Shadow(
                    offset: Offset(1, 1),
                    blurRadius: 2,
                    color: Colors.black,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
                  ? Colors.blue.withValues(alpha:0.8)
                  : Colors.green.withValues(alpha:0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha:0.3),
                width: 1,
              ),
            ),
            child: IconButton(
              onPressed: () {
                logDebug('Play icon tapped for ${game.exe.name}'); // Debug print
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
                size: _getCornerIconSize() + 2, // Slightly larger than corner icons but still proportional
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
              padding: EdgeInsets.all(_getSmallPadding() * 0.4),
              constraints: BoxConstraints(
                minWidth: _getCornerIconSize() + 10,
                minHeight: _getCornerIconSize() + 10,
              ),
            ),
          ),
        ),

        // Launch area (excluding corners where icons are)
        Positioned(
          left: _getIconAreaSize(), // Exclude left corner area for info icon
          right: _getIconAreaSize(), // Exclude right corner area for settings icon and delete icon
          top: _getIconAreaSize() - 10, // Exclude top area where icons are
          bottom: _getIconAreaSize(), // Exclude bottom area where delete icon is (increased exclusion)
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                // This area is for launching the game
                logDebug('Launch area tapped for ${game.exe.name}'); // Debug print
                onLaunch(game);
              },
              splashColor: Colors.white.withValues(alpha:0.1),
              highlightColor: Colors.white.withValues(alpha:0.05),
            ),
          ),
        ),

        // Center action button/indicator (Play/Stop/Loading/Error)
        Center(
          child: _buildCenterActionWidget(),
        ),

        // Delete icon - bottom-right (if delete callback is provided) - MUST be last for proper touch handling
        if (onDelete != null)
          Positioned(
            bottom: _getTopPadding(),
            right: _getTopPadding(),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha:0.8),
                borderRadius: BorderRadius.circular(_getBorderRadius() + 2),
                border: Border.all(
                  color: Colors.white.withValues(alpha:0.3),
                  width: 1,
                ),
              ),
              child: IconButton(
                onPressed: () {
                  logDebug(
                      'Delete icon tapped for ${game.exe.name}'); // Debug print
                  onDelete?.call(game);
                },
                icon: Icon(
                  Icons.delete_outline,
                  color: Colors.white,
                  size: _getCornerIconSize(),
                ),
                tooltip: 'Delete Game',
                padding: EdgeInsets.all(_getCornerIconSize() * 0.3),
                constraints: BoxConstraints(
                  minWidth: _getCornerIconSize() + 8,
                  minHeight: _getCornerIconSize() + 8,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCenterActionWidget() {
    switch (launchState) {
      case GameLaunchState.launching:
        return Container(
          padding: EdgeInsets.all(_getSmallPadding() * 2),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha:0.2),
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: _getCenterIconSize(),
            height: _getCenterIconSize(),
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            ),
          ),
        );
      case GameLaunchState.running:
        return Container(
          padding: EdgeInsets.all(_getSmallPadding() * 2),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha:0.2),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: () {
              logDebug('Stop icon tapped for ${game.exe.name}'); // Debug print
              onStop?.call(game);
            },
            icon: Icon(
              Icons.stop,
              color: Colors.red,
              size: _getCenterIconSize(),
            ),
            tooltip: 'Stop Game',
          ),
        );
      case GameLaunchState.failed:
        return Container(
          padding: EdgeInsets.all(_getSmallPadding() * 2),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha:0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.error_outline,
            color: Colors.orangeAccent,
            size: _getCenterIconSize(),
          ),
        );
      case GameLaunchState.idle:
        // Much smaller and subtle central indicator
        return Container(
          padding: EdgeInsets.all(_getSmallPadding()),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha:0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.gamepad,
            color: Colors.white.withValues(alpha:0.3),
            size: _getCenterIconSize() * 0.8,
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
  double _getBottomGradientHeight() {
    switch (coverSize) {
      case CoverSize.small:
        return 50.0;
      case CoverSize.medium:
        return 60.0;
      case CoverSize.large:
        return 70.0;
    }
  }

  double _getTopPadding() {
    switch (coverSize) {
      case CoverSize.small:
        return 6.0;
      case CoverSize.medium:
        return 8.0;
      case CoverSize.large:
        return 10.0;
    }
  }

  double _getIconAreaSize() {
    switch (coverSize) {
      case CoverSize.small:
        return 40.0;
      case CoverSize.medium:
        return 50.0;
      case CoverSize.large:
        return 60.0;
    }
  }

  double _getSmallPadding() {
    switch (coverSize) {
      case CoverSize.small:
        return 4.0;
      case CoverSize.medium:
        return 6.0;
      case CoverSize.large:
        return 8.0;
    }
  }

  double _getSmallIconSize() {
    switch (coverSize) {
      case CoverSize.small:
        return 10.0;
      case CoverSize.medium:
        return 12.0;
      case CoverSize.large:
        return 14.0;
    }
  }

  double _getSmallTextSize() {
    switch (coverSize) {
      case CoverSize.small:
        return 8.0;
      case CoverSize.medium:
        return 9.0;
      case CoverSize.large:
        return 10.0;
    }
  }

  double _getBorderRadius() {
    switch (coverSize) {
      case CoverSize.small:
        return 10.0;
      case CoverSize.medium:
        return 12.0;
      case CoverSize.large:
        return 14.0;
    }
  }

  double _getCornerIconSize() {
    switch (coverSize) {
      case CoverSize.small:
        return 8.0;
      case CoverSize.medium:
        return 9.0;
      case CoverSize.large:
        return 12.0;
    }
  }

  double _getTextSize() {
    switch (coverSize) {
      case CoverSize.small:
        return 12.0;
      case CoverSize.medium:
        return 14.0;
      case CoverSize.large:
        return 16.0;
    }
  }

  double _getCenterIconSize() {
    switch (coverSize) {
      case CoverSize.small:
        return 40.0;
      case CoverSize.medium:
        return 50.0;
      case CoverSize.large:
        return 60.0;
    }
  }
}
