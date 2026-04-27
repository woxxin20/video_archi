import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

import '../models/video_item.dart';
import '../config.dart';
import '../providers/virtual_help_provider.dart';

/// Fullscreen video player with 70% watch threshold tracking (Section 13).
class VideoPlayerScreen extends StatefulWidget {
  final VideoItem video;
  final String category;

  const VideoPlayerScreen({
    super.key,
    required this.video,
    required this.category,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _alreadyMarkedWatched = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final provider = context.read<VirtualHelpProvider>();
    final preloaded = provider.preloadService.consume(widget.video.id);

    if (preloaded != null) {
      _videoController = preloaded;
    } else {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.video.videoUrl),
      );
    }

    try {
      if (!_videoController.value.isInitialized) {
        await _videoController.initialize();
      }

      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoController.value.aspectRatio,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 48, color: Colors.white70),
                  const SizedBox(height: 16),
                  Text(
                    'Unable to play video.\nPlease check your internet connection.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          );
        },
      );

      // Track watch progress (Section 13)
      _videoController.addListener(_onProgressUpdate);

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  /// Section 13: Mark watched at 70% threshold.
  void _onProgressUpdate() {
    if (_alreadyMarkedWatched) return;

    final pos = _videoController.value.position.inMilliseconds;
    final dur = _videoController.value.duration.inMilliseconds;

    if (dur > 0) {
      final progress = pos / dur;
      if (progress >= VirtualHelpConfig.watchThreshold) {
        _alreadyMarkedWatched = true;
        context.read<VirtualHelpProvider>().markVideoWatched(
              widget.video.id,
              widget.category,
            );
      }
    }
  }

  @override
  void dispose() {
    _videoController.removeListener(_onProgressUpdate);
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.video.title, style: const TextStyle(fontSize: 16)),
      ),
      body: _hasError
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.white70),
                  const SizedBox(height: 16),
                  const Text(
                    'No internet connection.\nPlease connect to watch videos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _hasError = false);
                      _initPlayer();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _chewieController != null
              ? Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Chewie(controller: _chewieController!),
                      ),
                    ),
                    // Video info below player
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.video.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.video.description,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : const Center(child: CircularProgressIndicator()),
    );
  }
}
