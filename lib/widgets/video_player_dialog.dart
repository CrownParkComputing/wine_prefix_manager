import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class VideoPlayerDialog extends StatelessWidget {
  final String videoId;

  const VideoPlayerDialog({super.key, required this.videoId});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Video Player'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('This will open the video in your browser.'),
          const SizedBox(height: 16),
          Image.network(
            'https://img.youtube.com/vi/$videoId/0.jpg',
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.error);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final url = Uri.parse('https://www.youtube.com/watch?v=$videoId');
            launchUrl(url, mode: LaunchMode.externalApplication);
            Navigator.pop(context);
          },
          child: const Text('Play Video'),
        ),
      ],
    );
  }
}
