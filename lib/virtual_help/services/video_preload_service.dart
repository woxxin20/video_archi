import 'package:better_player_plus/better_player_plus.dart';
import '../models/video_item.dart';

/// Handles pre-initialization of video controllers to ensure near-instant playback.
/// Implements Section 14: "Video Pre-Initialization" with HLS support.
class VideoPreloadService {
  BetterPlayerController? _preloadedController;
  String? _preloadedVideoId;

  BetterPlayerController? get preloadedController => _preloadedController;
  String? get preloadedVideoId => _preloadedVideoId;

  /// Pre-initializes a video controller for the given video.
  /// Used for "slot 1 only" of the Tips category to improve UX.
  Future<void> preloadVideo(VideoItem video) async {
    // If already preloaded, don't do it again
    if (_preloadedVideoId == video.id) return;

    // Dispose old controller if exists
    await dispose();

    _preloadedVideoId = video.id;

    // ── Data source: HLS master playlist ─────────────────────────────
    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      video.streamUrl,
      videoFormat: BetterPlayerVideoFormat.hls,
      cacheConfiguration: BetterPlayerCacheConfiguration(
        useCache: true,
        maxCacheSize: 20 * 1024 * 1024, // 20MB cache for preload
        maxCacheFileSize: 10 * 1024 * 1024, // 10MB per video
      ),
    );

    // ── Player configuration ──────────────────────────────────────────
    final config = BetterPlayerConfiguration(
      autoPlay: false, // Don't auto-play preloaded content
      looping: false,
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: false, // Hide controls for preloaded content
      ),
    );

    _preloadedController = BetterPlayerController(config);

    try {
      await _preloadedController!.setupDataSource(dataSource);
      // HLS stream will start buffering but won't play
    } catch (e) {
      // If preload fails, just clear it so we don't try to use a broken controller
      await dispose();
    }
  }

  /// Take ownership of the preloaded controller.
  /// The caller is responsible for disposing it.
  BetterPlayerController? consume(String videoId) {
    if (_preloadedVideoId == videoId) {
      final controller = _preloadedController;
      _preloadedController = null;
      _preloadedVideoId = null;
      return controller;
    }
    return null;
  }

  Future<void> dispose() async {
    _preloadedController?.dispose();
    _preloadedController = null;
    _preloadedVideoId = null;
  }
}
