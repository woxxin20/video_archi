import 'dart:developer';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/video_item.dart';
import '../config.dart';
import '../providers/virtual_help_provider.dart';

/// Fullscreen video player with HLS audio track selection and 70% watch threshold tracking.
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
  late BetterPlayerController _controller;
  bool _alreadyMarkedWatched = false;
  bool _hasError = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final provider = context.read<VirtualHelpProvider>();
    final preloaded = provider.preloadService.consume(widget.video.id);

    log('[VideoPlayer] Initializing HLS player for video: ${widget.video.id}');
    log('[VideoPlayer] Stream URL: ${widget.video.streamUrl}');
    log('[VideoPlayer] Preferred audio: ${widget.video.preferredAudioLang}');

    // ── Test with direct network URL first ────────────────────────────
    try {
      // First try without HLS format detection
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.video.streamUrl,
        videoFormat: BetterPlayerVideoFormat.hls,
        cacheConfiguration: BetterPlayerCacheConfiguration(
          useCache: true,
          maxCacheSize: 50 * 1024 * 1024, // 50MB total cache
          maxCacheFileSize: 10 * 1024 * 1024, // 10MB per video
        ),
      );

      // ── Player configuration ──────────────────────────────────────────
      final config = BetterPlayerConfiguration(
        aspectRatio: 9 / 16, // vertical video
        fit: BoxFit.cover,
        autoPlay: true,
        looping: false,
        fullScreenByDefault: true,
        allowedScreenSleep: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControlsOnInitialize: false,
          enableFullscreen: true,
          enableProgressBar: true,
          enableSkips: false, // health videos — no skipping
          enableMute: true,
          enablePlaybackSpeed: false, // keep it simple for health content
          progressBarPlayedColor: Colors.pinkAccent,
          progressBarBufferedColor: Colors.pink.withValues(alpha: 0.3),
          controlBarColor: Colors.black54,
        ),
      );

      _controller = BetterPlayerController(config);
      _controller.addEventsListener(_onPlayerEvent);

      log('[VideoPlayer] Setting up data source...');
      await _controller.setupDataSource(dataSource);

      // If we have a preloaded controller, dispose it since we're using HLS
      if (preloaded != null) {
        preloaded.dispose();
      }

      _isInitialized = true;
      log('[VideoPlayer] HLS player initialized successfully');

      if (mounted) setState(() {});
    } catch (e, stackTrace) {
      log('[VideoPlayer] HLS initialization failed: $e');
      log('[VideoPlayer] Stack trace: $stackTrace');

      // Try fallback to basic video player if HLS fails or resource is unavailable
      final errorStr = e.toString();
      if (errorStr.contains('HLS') || 
          errorStr.contains('m3u8') || 
          errorStr.contains('resource unavailable')) {
        log('[VideoPlayer] Trying fallback to direct video stream...');
        await _tryFallbackPlayer();
      } else {
        if (mounted) setState(() => _hasError = true);
      }
    }
  }

  Future<void> _tryFallbackPlayer() async {
    try {
      // Try to get the video segment directly
      final videoStreamUrl = widget.video.streamUrl.replaceFirst(
        '/master.m3u8',
        '/video/stream.m3u8',
      );

      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        videoStreamUrl,
        cacheConfiguration: BetterPlayerCacheConfiguration(
          useCache: true,
          maxCacheSize: 50 * 1024 * 1024,
          maxCacheFileSize: 10 * 1024 * 1024,
        ),
      );

      final config = BetterPlayerConfiguration(
        aspectRatio: 9 / 16,
        fit: BoxFit.cover,
        autoPlay: true,
        looping: false,
        fullScreenByDefault: true,
        allowedScreenSleep: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControlsOnInitialize: false,
          enableFullscreen: true,
          enableProgressBar: true,
          enableSkips: false,
          enableMute: true,
          enablePlaybackSpeed: false,
          progressBarPlayedColor: Colors.pinkAccent,
          progressBarBufferedColor: Colors.pink.withValues(alpha: 0.3),
          controlBarColor: Colors.black54,
        ),
      );

      _controller = BetterPlayerController(config);
      _controller.addEventsListener(_onPlayerEvent);

      log('[VideoPlayer] Setting up fallback data source: $videoStreamUrl');
      await _controller.setupDataSource(dataSource);

      _isInitialized = true;
      log('[VideoPlayer] Fallback player initialized successfully');

      if (mounted) setState(() {});
    } catch (e, stackTrace) {
      log('[VideoPlayer] Fallback player failed: $e');
      log('[VideoPlayer] Fallback stack trace: $stackTrace');
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      // ── Video initialized: select audio track ──────────────────────
      case BetterPlayerEventType.initialized:
        _selectAudioTrack();
        break;

      // ── Track progress for watch threshold ────────────────────────
      case BetterPlayerEventType.progress:
        _checkWatchProgress();
        break;

      // ── Video finished: mark watched (safety net) ─────────────────
      case BetterPlayerEventType.finished:
        if (!_alreadyMarkedWatched) {
          _markWatched();
        }
        break;

      default:
        break;
    }
  }

  /// Selects the audio track matching preferred language.
  /// Note: better_player audio track API is complex, simplified for now.
  void _selectAudioTrack() {
    log('[VideoPlayer] Audio track selection not implemented in this version');
    log('[VideoPlayer] Using default audio track from HLS stream');
  }

  void _checkWatchProgress() {
    if (_alreadyMarkedWatched) return;

    final position = _controller.videoPlayerController?.value.position;
    final duration = _controller.videoPlayerController?.value.duration;

    if (position == null || duration == null) return;
    if (duration.inSeconds == 0) return;

    final progress = position.inSeconds / duration.inSeconds;

    if (progress >= VirtualHelpConfig.watchThreshold) {
      _alreadyMarkedWatched = true;
      _markWatched();
    }
  }

  void _markWatched() {
    log('[VideoPlayer] Marking video as watched: ${widget.video.id}');
    context.read<VirtualHelpProvider>().markVideoWatched(
      widget.video.id,
      widget.category,
    );
  }

  @override
  void dispose() {
    _controller.removeEventsListener(_onPlayerEvent);
    _controller.dispose();
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
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.white70,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load video',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Stream URL: ${widget.video.streamUrl}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
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
          : _isInitialized
          ? Column(
              children: [
                // ── Player ───────────────────────────────────────────────
                Expanded(child: BetterPlayer(controller: _controller)),

                // ── Title + Description ───────────────────────────────────
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
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),

                      // ── Audio language indicator ───────────────────────
                      if (widget.video.videoLangResolved !=
                          widget.video.preferredAudioLang)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _AudioFallbackBadge(
                            requestedLang: widget.video.preferredAudioLang,
                            resolvedLang: widget.video.videoLangResolved,
                          ),
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

// ── Small UI badge shown when audio fell back to another language ─────
class _AudioFallbackBadge extends StatelessWidget {
  final String requestedLang;
  final String resolvedLang;

  const _AudioFallbackBadge({
    required this.requestedLang,
    required this.resolvedLang,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Text(
        'Playing in ${_langName(resolvedLang)} (${_langName(requestedLang)} coming soon)',
        style: const TextStyle(color: Colors.orange, fontSize: 12),
      ),
    );
  }

  String _langName(String code) {
    const names = {
      'en': 'English',
      'hi': 'Hindi',
      'gu': 'Gujarati',
      'mr': 'Marathi',
      'ta': 'Tamil',
      'te': 'Telugu',
      'bn': 'Bengali',
      'pa': 'Punjabi',
      'ur': 'Urdu',
      'ar': 'Arabic',
      'fr': 'French',
      'es': 'Spanish',
      'de': 'German',
      'pt': 'Portuguese',
      'ru': 'Russian',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'id': 'Indonesian',
      'tr': 'Turkish',
      'sw': 'Swahili',
      'vi': 'Vietnamese',
      'fa': 'Persian',
      'am': 'Amharic',
      'af': 'Afrikaans',
      'tl': 'Filipino',
      'th': 'Thai',
    };
    return names[code] ?? code.toUpperCase();
  }
}
