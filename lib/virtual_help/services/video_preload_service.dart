import 'package:video_player/video_player.dart';
import '../models/video_item.dart';

/// Handles pre-initialization of video controllers to ensure near-instant playback.
/// Implements Section 14: "Video Pre-Initialization".
class VideoPreloadService {
  VideoPlayerController? _preloadedController;
  String? _preloadedVideoId;

  VideoPlayerController? get preloadedController => _preloadedController;
  String? get preloadedVideoId => _preloadedVideoId;

  /// Pre-initializes a video controller for the given video.
  /// Used for "slot 1 only" of the Tips category to improve UX.
  Future<void> preloadVideo(VideoItem video) async {
    // If already preloaded, don't do it again
    if (_preloadedVideoId == video.id) return;

    // Dispose old controller if exists
    await dispose();

    _preloadedVideoId = video.id;
    _preloadedController = VideoPlayerController.networkUrl(Uri.parse(video.videoUrl));

    try {
      await _preloadedController!.initialize();
      // Start buffering but don't play
    } catch (e) {
      // If preload fails, just clear it so we don't try to use a broken controller
      await dispose();
    }
  }

  /// Take ownership of the preloaded controller.
  /// The caller is responsible for disposing it.
  VideoPlayerController? consume(String videoId) {
    if (_preloadedVideoId == videoId) {
      final controller = _preloadedController;
      _preloadedController = null;
      _preloadedVideoId = null;
      return controller;
    }
    return null;
  }

  Future<void> dispose() async {
    await _preloadedController?.dispose();
    _preloadedController = null;
    _preloadedVideoId = null;
  }
}
