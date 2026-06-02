import 'dart:developer';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../models/video_item.dart';
import '../config.dart';
import '../providers/virtual_help_provider.dart';
import 'virtual_help_theme.dart';

/// Full-screen video player.
/// Business logic (HLS init, watch threshold, audio track) is unchanged.
/// UI matches the Virtual Help design: dark overlay with category pill,
/// serif title, progress bar, and Prev/Next navigation.
class VideoPlayerScreen extends StatefulWidget {
  final VideoItem video;
  final String category;

  /// All videos in this category — enables Prev/Next navigation.
  final List<VideoItem> categoryVideos;

  const VideoPlayerScreen({
    super.key,
    required this.video,
    required this.category,
    this.categoryVideos = const [],
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late BetterPlayerController _controller;
  bool _alreadyMarkedWatched = false;
  bool _hasError = false;
  bool _isInitialized = false;

  late int _currentIndex;
  late List<VideoItem> _videos;

  bool _isInitCalled = false;

  @override
  void initState() {
    super.initState();
    _videos = widget.categoryVideos.isNotEmpty
        ? widget.categoryVideos
        : [widget.video];
    _currentIndex = _videos.indexWhere((v) => v.id == widget.video.id);
    if (_currentIndex < 0) _currentIndex = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitCalled) {
      _isInitCalled = true;
      _initPlayer(_videos[_currentIndex]);
    }
  }

  VideoItem get _currentVideo => _videos[_currentIndex];

  String get _categoryLabel =>
      VirtualHelpTheme.categoryLabel[widget.category] ??
      widget.category.toUpperCase();

  Color get _accent =>
      VirtualHelpTheme.categoryAccent[widget.category] ?? VirtualHelpTheme.brand;

  // ═══════════════════════════════════════════════════════
  //  HLS PLAYER INIT (unchanged business logic)
  // ═══════════════════════════════════════════════════════

  Future<void> _initPlayer(VideoItem video) async {
    // Capture screen size BEFORE any async gap (BuildContext rule).
    final screen = MediaQuery.of(context).size;
    final screenAspect = screen.width / screen.height;

    setState(() {
      _hasError = false;
      _isInitialized = false;
    });

    final provider = context.read<VirtualHelpProvider>();
    final preloaded = provider.preloadService.consume(video.id);

    log('[VideoPlayer] Initializing for: ${video.id}');
    log('[VideoPlayer] Stream URL: ${video.streamUrl}');

    try {
      final response = await http.get(Uri.parse(video.streamUrl));
      log('[VideoPlayer] HTTP status: ${response.statusCode}');
    } catch (e) {
      log('[VideoPlayer] Pre-check failed: $e');
    }

    try {
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        video.streamUrl,
        videoFormat: BetterPlayerVideoFormat.hls,
        cacheConfiguration: BetterPlayerCacheConfiguration(useCache: false),
      );

      // Use the SCREEN's aspect ratio so BetterPlayer's internal AspectRatio
      // widget matches the device exactly — combined with fit: cover this
      // gives true full-screen reel behaviour on any phone.
      final config = BetterPlayerConfiguration(
        aspectRatio: screenAspect,
        fit: BoxFit.cover,
        autoPlay: true,
        looping: false,
        fullScreenByDefault: false,
        allowedScreenSleep: false,
        expandToFill: true,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControls: false,
          showControlsOnInitialize: false,
          enableFullscreen: false,
          enableProgressBar: false,
          enableSkips: false,
          enableMute: false,
          enablePlaybackSpeed: false,
          controlBarColor: Colors.transparent,
        ),
      );

      _controller = BetterPlayerController(config);
      _controller.addEventsListener(_onPlayerEvent);

      await _controller.setupDataSource(dataSource);
      // Belt-and-suspenders: override aspect at runtime too, in case the
      // source video's intrinsic aspect would otherwise re-shape the box.
      _controller.setOverriddenAspectRatio(screenAspect);

      preloaded?.dispose();

      if (mounted) setState(() => _isInitialized = true);
    } catch (e, st) {
      log('[VideoPlayer] HLS init failed: $e\n$st');
      await _tryFallback(video, screenAspect);
    }
  }

  Future<void> _tryFallback(VideoItem video, double screenAspect) async {
    try {
      final fallbackUrl = video.streamUrl.replaceFirst(
        '/master.m3u8',
        '/video/stream.m3u8',
      );
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        fallbackUrl,
        cacheConfiguration: BetterPlayerCacheConfiguration(
          useCache: true,
          maxCacheSize: 50 * 1024 * 1024,
          maxCacheFileSize: 10 * 1024 * 1024,
        ),
      );
      final config = BetterPlayerConfiguration(
        aspectRatio: screenAspect,
        fit: BoxFit.cover,
        autoPlay: true,
        looping: false,
        fullScreenByDefault: false,
        allowedScreenSleep: false,
        expandToFill: true,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControls: false,
          showControlsOnInitialize: false,
          enableFullscreen: false,
          enableProgressBar: false,
          enableSkips: false,
          enableMute: false,
          enablePlaybackSpeed: false,
          controlBarColor: Colors.transparent,
        ),
      );
      _controller = BetterPlayerController(config);
      _controller.addEventsListener(_onPlayerEvent);
      await _controller.setupDataSource(dataSource);
      _controller.setOverriddenAspectRatio(screenAspect);
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      log('[VideoPlayer] Fallback failed: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        if (mounted) {
          final screen = MediaQuery.of(context).size;
          final screenAspect = screen.width / screen.height;
          _controller.setOverriddenAspectRatio(screenAspect);
        }
        _selectPreferredAudioTrack();
        break;
      case BetterPlayerEventType.progress:
        _checkWatchProgress();
        break;
      case BetterPlayerEventType.finished:
        if (!_alreadyMarkedWatched) _markWatched();
        break;
      default:
        break;
    }
  }

  /// Selects the HLS audio track matching `preferred_audio_lang` from the
  /// catalog, with fallback chain per architecture §5.3:
  /// requested → hi (regional) → en (guaranteed) → first available.
  void _selectPreferredAudioTrack() {
    final tracks = _controller.betterPlayerAsmsAudioTracks;
    if (tracks == null || tracks.isEmpty) {
      log('[VideoPlayer] No alternate audio tracks available on stream');
      return;
    }

    final preferred = _currentVideo.preferredAudioLang.toLowerCase();

    BetterPlayerAsmsAudioTrack? match;
    String? matchReason;

    // 1. Exact preferred language match
    match = _firstWhereLang(tracks, preferred);
    if (match != null) matchReason = 'preferred ($preferred)';

    // 2. Regional fallback — Hindi for sub-continent locales
    if (match == null) {
      match = _firstWhereLang(tracks, 'hi');
      if (match != null) matchReason = 'regional fallback (hi)';
    }

    // 3. English — always guaranteed by server
    if (match == null) {
      match = _firstWhereLang(tracks, 'en');
      if (match != null) matchReason = 'final fallback (en)';
    }

    // 4. First track — last resort
    match ??= tracks.first;
    matchReason ??= 'first available (${match.language ?? '?'})';

    log('[VideoPlayer] Audio track selected: $matchReason');
    // setAudioTrack throws MissingPluginException on iOS (better_player_plus
    // doesn't implement it natively). Swallow it — the server now bakes the
    // right language as DEFAULT=YES into master.m3u8, so the player picks
    // the right track automatically and this call is best-effort backup.
    try {
      _controller.setAudioTrack(match);
    } catch (e) {
      log('[VideoPlayer] setAudioTrack ignored (platform): $e');
    }
  }

  BetterPlayerAsmsAudioTrack? _firstWhereLang(
    List<BetterPlayerAsmsAudioTrack> tracks,
    String lang,
  ) {
    for (final t in tracks) {
      if ((t.language ?? '').toLowerCase() == lang) return t;
    }
    return null;
  }

  void _checkWatchProgress() {
    if (_alreadyMarkedWatched) return;
    final pos = _controller.videoPlayerController?.value.position;
    final dur = _controller.videoPlayerController?.value.duration;
    if (pos == null || dur == null || dur.inSeconds == 0) return;
    if (pos.inSeconds / dur.inSeconds >= VirtualHelpConfig.watchThreshold) {
      _alreadyMarkedWatched = true;
      _markWatched();
    }
  }

  void _markWatched() {
    log('[VideoPlayer] Marking watched: ${_currentVideo.id}');
    context.read<VirtualHelpProvider>().markVideoWatched(
          _currentVideo.id,
          widget.category,
        );
  }

  void _navigateTo(int newIndex) {
    if (newIndex < 0 || newIndex >= _videos.length) return;
    _controller.removeEventsListener(_onPlayerEvent);
    _controller.dispose();
    _alreadyMarkedWatched = false;
    setState(() => _currentIndex = newIndex);
    _initPlayer(_videos[newIndex]);
  }

  @override
  void dispose() {
    _controller.removeEventsListener(_onPlayerEvent);
    _controller.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      backgroundColor: VirtualHelpTheme.playerBg,
      body: Stack(
        children: [
          // ── Ambient background gradient ──────────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-0.8, -1),
                  end: const Alignment(0.8, 1),
                  colors: [
                    _accent.withValues(alpha: 0.22),
                    _accent.withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ),

          // ── Main content ─────────────────────────────────────────────
          if (_hasError)
            _ErrorView(
              video: _currentVideo,
              onRetry: () => _initPlayer(_currentVideo),
            )
          else if (_isInitialized)
            Positioned.fill(child: _PlayerView(controller: _controller))
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),

          // ── Top bar ──────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopBar(
              categoryLabel: _categoryLabel,
              currentIndex: _currentIndex,
              total: _videos.length,
              onBack: () {
                SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
                Navigator.of(context).pop();
              },
            ),
          ),

          // ── Bottom overlay ───────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomOverlay(
              video: _currentVideo,
              accent: _accent,
              categoryLabel: _categoryLabel,
              currentIndex: _currentIndex,
              total: _videos.length,
              controller: _isInitialized ? _controller : null,
              onPrev: _currentIndex > 0 ? () => _navigateTo(_currentIndex - 1) : null,
              onNext: _currentIndex < _videos.length - 1
                  ? () => _navigateTo(_currentIndex + 1)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Player view ──────────────────────────────────────────────────────
// Instagram-reel style: 9:16 video fills the entire screen on every phone.
// The controller is configured with `aspectRatio = screen.aspectRatio` and
// `fit: BoxFit.cover`, so BetterPlayer's own AspectRatio widget already
// matches the screen and the video pixels cover it (cropping sides).
// We just expand to fill the parent and clip any overflow.

class _PlayerView extends StatelessWidget {
  final BetterPlayerController controller;
  const _PlayerView({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox.expand(
        child: BetterPlayer(controller: controller),
      ),
    );
  }
}

// ── Top bar ──────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String categoryLabel;
  final int currentIndex;
  final int total;
  final VoidCallback onBack;

  const _TopBar({
    required this.categoryLabel,
    required this.currentIndex,
    required this.total,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top + 14, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Back button
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: const Icon(Icons.chevron_left_rounded,
                  color: Colors.white, size: 22),
            ),
          ),

          const Spacer(),

          // Category + count
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Virtual Help · $categoryLabel',
                style: VirtualHelpTheme.sans(
                  size: 9,
                  weight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.5),
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Video ${currentIndex + 1} of $total',
                style: VirtualHelpTheme.serif(
                  size: 14,
                  weight: FontWeight.w300,
                  color: Colors.white,
                  italic: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Bottom overlay ───────────────────────────────────────────────────

class _BottomOverlay extends StatelessWidget {
  final VideoItem video;
  final Color accent;
  final String categoryLabel;
  final int currentIndex;
  final int total;
  final BetterPlayerController? controller;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _BottomOverlay({
    required this.video,
    required this.accent,
    required this.categoryLabel,
    required this.currentIndex,
    required this.total,
    required this.controller,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: const [0, 1],
          colors: [
            Colors.black.withValues(alpha: 0.78),
            Colors.transparent,
          ],
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 28, 20, bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Category pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_rounded, color: Colors.white, size: 10),
                const SizedBox(width: 4),
                Text(
                  categoryLabel == 'Tips' ? 'Daily Tip' : categoryLabel,
                  style: VirtualHelpTheme.sans(
                    size: 8.5,
                    weight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.07,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Title
          Text(
            video.title,
            style: VirtualHelpTheme.serif(
              size: 20,
              weight: FontWeight.w200,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 6),

          // Description
          Text(
            video.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: VirtualHelpTheme.sans(
              size: 10,
              color: Colors.white.withValues(alpha: 0.6),
              height: 1.6,
            ),
          ),

          const SizedBox(height: 14),

          // Progress bar
          _ProgressBar(controller: controller),

          const SizedBox(height: 14),

          // Navigation
          Row(
            children: [
              // Prev
              Expanded(
                child: _NavButton(
                  label: 'Prev',
                  icon: Icons.chevron_left_rounded,
                  iconOnLeft: true,
                  enabled: onPrev != null,
                  onTap: onPrev,
                ),
              ),

              // Dot indicators
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: List.generate(total, (i) {
                    return Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == currentIndex
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.28),
                      ),
                    );
                  }),
                ),
              ),

              // Next
              Expanded(
                child: _NavButton(
                  label: 'Next',
                  icon: Icons.chevron_right_rounded,
                  iconOnLeft: false,
                  enabled: onNext != null,
                  onTap: onNext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatefulWidget {
  final BetterPlayerController? controller;
  const _ProgressBar({this.controller});

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?.addEventsListener(_onEvent);
  }

  void _onEvent(BetterPlayerEvent event) {
    if (!mounted) return;
    if (event.betterPlayerEventType == BetterPlayerEventType.progress) {
      final pos = widget.controller?.videoPlayerController?.value.position;
      final dur = widget.controller?.videoPlayerController?.value.duration;
      if (pos != null && dur != null && dur.inSeconds > 0) {
        setState(() => _progress = pos.inSeconds / dur.inSeconds);
      }
    }
  }

  @override
  void dispose() {
    widget.controller?.removeEventsListener(_onEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        widthFactor: _progress.clamp(0.0, 1.0),
        alignment: Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool iconOnLeft;
  final bool enabled;
  final VoidCallback? onTap;

  const _NavButton({
    required this.label,
    required this.icon,
    required this.iconOnLeft,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: iconOnLeft
                ? [
                    Icon(icon,
                        color: Colors.white.withValues(alpha: 0.75), size: 18),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: VirtualHelpTheme.sans(
                        size: 10,
                        weight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ]
                : [
                    Text(
                      label,
                      style: VirtualHelpTheme.sans(
                        size: 10,
                        weight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(icon,
                        color: Colors.white.withValues(alpha: 0.75), size: 18),
                  ],
          ),
        ),
      ),
    );
  }
}

// ── Error view ───────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onRetry;
  const _ErrorView({required this.video, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              'Failed to load video',
              style: VirtualHelpTheme.sans(
                  size: 16, weight: FontWeight.w600, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              video.streamUrl,
              style: VirtualHelpTheme.sans(
                  size: 10, color: Colors.white.withValues(alpha: 0.5)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: VirtualHelpTheme.brand),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Audio fallback badge (kept for compatibility) ─────────────────────

class AudioFallbackBadge extends StatelessWidget {
  final String requestedLang;
  final String resolvedLang;
  const AudioFallbackBadge(
      {super.key, required this.requestedLang, required this.resolvedLang});

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
        'Playing in $resolvedLang ($requestedLang coming soon)',
        style: const TextStyle(color: Colors.orange, fontSize: 12),
      ),
    );
  }
}
