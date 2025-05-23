import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import '../models/prefix_models.dart';

class GameInfoModal extends StatefulWidget {
  final GameEntry game;
  final VoidCallback? onLaunchGame;
  final Function(GameEntry)? onUpdateMetadata;

  const GameInfoModal({
    super.key,
    required this.game,
    this.onLaunchGame,
    this.onUpdateMetadata,
  });

  @override
  State<GameInfoModal> createState() => _GameInfoModalState();
}

class _GameInfoModalState extends State<GameInfoModal> {
  late ScrollController _imageScrollController;

  @override
  void initState() {
    super.initState();
    _imageScrollController = ScrollController();
  }

  @override
  void dispose() {
    _imageScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with close button
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.game.exe.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cover image and basic info row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cover image
                        Container(
                          width: 150,
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _buildCoverImage(),
                          ),
                        ),
                        const SizedBox(width: 20),
                        
                        // Basic info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoCard('Game Information', [
                                _buildInfoRow('Name', widget.game.exe.name),
                                _buildInfoRow('Path', widget.game.exe.path),
                                _buildInfoRow('Prefix', widget.game.prefix.name),
                                _buildInfoRow('Architecture', widget.game.prefix.architecture),
                                _buildInfoRow('Type', widget.game.prefix.type == PrefixType.wine ? 'Wine' : 'Proton'),
                                _buildInfoRow('Category', widget.game.exe.category ?? 'Uncategorized'),
                                if (widget.game.exe.playTimeMinutes != null && widget.game.exe.playTimeMinutes! > 0)
                                  _buildInfoRow('Play Time', _formatPlayTime(widget.game.exe.playTimeMinutes!)),
                                if (widget.game.exe.lastPlayed != null)
                                  _buildInfoRow('Last Played', DateFormat('MMM dd, yyyy HH:mm').format(widget.game.exe.lastPlayed!)),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Description
                    if (widget.game.exe.description != null && widget.game.exe.description!.isNotEmpty)
                      _buildInfoCard('Description', [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(
                            widget.game.exe.description!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ]),
                    
                    const SizedBox(height: 20),
                    
                    // Image Carousel
                    _buildInfoCard('Images', [
                      SizedBox(
                        height: 220,
                        child: _buildImageCarousel(context),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            
            // Action buttons
            const Divider(),
            Row(
              children: [
                if (widget.onUpdateMetadata != null)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onUpdateMetadata!(widget.game);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Update Metadata'),
                  ),
                const Spacer(),
                if (widget.onLaunchGame != null)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onLaunchGame!();
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Launch Game'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    if (widget.game.exe.localCoverPath != null && widget.game.exe.localCoverPath!.isNotEmpty) {
      return Image.file(
        File(widget.game.exe.localCoverPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackCover(),
      );
    } else if (widget.game.exe.coverUrl != null && widget.game.exe.coverUrl!.isNotEmpty) {
      return Image.network(
        widget.game.exe.coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackCover(),
      );
    } else {
      return _buildFallbackCover();
    }
  }

  Widget _buildFallbackCover() {
    return Container(
      color: Colors.grey[800],
      child: Center(
        child: Text(
          widget.game.exe.name.length >= 2
              ? widget.game.exe.name.substring(0, 2).toUpperCase()
              : widget.game.exe.name.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  String _formatPlayTime(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      if (remainingMinutes == 0) {
        return '${hours}h';
      } else {
        return '${hours}h ${remainingMinutes}m';
      }
    }
  }

  Widget _buildImageCarousel(BuildContext context) {
    // Collect all images (cover + screenshots)
    List<String> allImages = [];
    List<String> imageTypes = [];
    
    // Add cover image if available
    if (widget.game.exe.localCoverPath != null && widget.game.exe.localCoverPath!.isNotEmpty) {
      allImages.add(widget.game.exe.localCoverPath!);
      imageTypes.add('local');
    } else if (widget.game.exe.coverUrl != null && widget.game.exe.coverUrl!.isNotEmpty) {
      allImages.add(widget.game.exe.coverUrl!);
      imageTypes.add('network');
    }
    
    // Add screenshots
    for (final screenshotUrl in widget.game.exe.screenshotUrls) {
      allImages.add(screenshotUrl);
      imageTypes.add('network');
    }
    
    if (allImages.isEmpty) {
      return Container(
        color: Colors.grey[300],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
              SizedBox(height: 8),
              Text('No images available', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scroll hint text if there are multiple images
        if (allImages.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Row(
              children: [
                const Icon(Icons.swipe, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Swipe to see all ${allImages.length} images • Tap to expand',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        // Image carousel
        Expanded(
          child: Stack(
            children: [
              Listener(
                onPointerSignal: (pointerSignal) {
                  if (pointerSignal is PointerScrollEvent) {
                    // Convert vertical mouse wheel scroll to horizontal scroll
                    final scrollDelta = pointerSignal.scrollDelta.dy;
                    _imageScrollController.animateTo(
                      _imageScrollController.offset + scrollDelta,
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOut,
                    );
                  }
                },
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                    },
                    scrollbars: false,
                  ),
                  child: ListView.builder(
                    controller: _imageScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    itemCount: allImages.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: GestureDetector(
                          onTap: () => _showExpandedImageDialog(context, allImages, imageTypes, index),
                          child: Container(
                            width: 150,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                children: [
                                  // Image
                                  _buildCarouselImage(allImages[index], imageTypes[index]),
                                  // Overlay with index indicator
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${index + 1}/${allImages.length}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Click indicator
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.zoom_in,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                  // Image type indicator (cover vs screenshot)
                                  if (index == 0 && (widget.game.exe.localCoverPath != null || widget.game.exe.coverUrl != null))
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.8),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'COVER',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Left scroll indicator
              if (allImages.length > 1)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 20,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.white.withOpacity(0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.chevron_left,
                        color: Colors.grey,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              // Right scroll indicator
              if (allImages.length > 1)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 20,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          Colors.white.withOpacity(0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.chevron_right,
                        color: Colors.grey,
                        size: 20,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildCarouselImage(String imagePath, String imageType) {
    if (imageType == 'local') {
      return Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _buildErrorImage(),
      );
    } else {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _buildErrorImage(),
      );
    }
  }
  
  Widget _buildErrorImage() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
      ),
    );
  }
  
  void _showExpandedImageDialog(BuildContext context, List<String> images, List<String> imageTypes, int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _ExpandedImageDialog(
        images: images,
        imageTypes: imageTypes,
        initialIndex: initialIndex,
        gameName: widget.game.exe.name,
      ),
    );
  }
}

class _ExpandedImageDialog extends StatefulWidget {
  final List<String> images;
  final List<String> imageTypes;
  final int initialIndex;
  final String gameName;

  const _ExpandedImageDialog({
    required this.images,
    required this.imageTypes,
    required this.initialIndex,
    required this.gameName,
  });

  @override
  State<_ExpandedImageDialog> createState() => _ExpandedImageDialogState();
}

class _ExpandedImageDialogState extends State<_ExpandedImageDialog> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black87,
      child: Stack(
        children: [
          // Image viewer
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  boundaryMargin: const EdgeInsets.all(20),
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: widget.imageTypes[index] == 'local'
                      ? Image.file(
                          File(widget.images[index]),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => _buildExpandedErrorImage(),
                        )
                      : Image.network(
                          widget.images[index],
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => _buildExpandedErrorImage(),
                        ),
                ),
              );
            },
          ),
          
          // Top bar with close button and title
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      tooltip: 'Close',
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        widget.gameName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Bottom bar with navigation and counter
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Previous button
                    IconButton(
                      onPressed: _currentIndex > 0
                          ? () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          : null,
                      icon: Icon(
                        Icons.chevron_left,
                        color: _currentIndex > 0 ? Colors.white : Colors.grey,
                        size: 32,
                      ),
                      tooltip: 'Previous',
                    ),
                    
                    // Image counter
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${widget.images.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    
                    // Next button
                    IconButton(
                      onPressed: _currentIndex < widget.images.length - 1
                          ? () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          : null,
                      icon: Icon(
                        Icons.chevron_right,
                        color: _currentIndex < widget.images.length - 1 ? Colors.white : Colors.grey,
                        size: 32,
                      ),
                      tooltip: 'Next',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedErrorImage() {
    return Container(
      width: 300,
      height: 300,
      color: Colors.grey[800],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Failed to load image',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
} 