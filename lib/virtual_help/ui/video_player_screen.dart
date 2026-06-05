import 'dart:developer';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/feed_entry.dart';
import '../models/video_item.dart';
import '../providers/virtual_help_provider.dart';
import 'virtual_help_theme.dart';

/// Instagram-Reels-style full-screen vertical video player.
///
/// - Vertical swipe between videos via [PageView].
/// - Each reel fills the entire screen (BoxFit.cover, no letterbox).
/// - Adjacent controllers are pre-warmed for snappy swipes; far ones
///   are disposed to keep memory bounded.
/// - Watch-progress (70 %) → markVideoWatched is preserved.
/// - HLS audio variant selection is delegated to `setAudioTrack` on the
///   player using the catalog's `preferred_audio_lang`.
class VideoPlayerScreen extends StatefulWidget {
  /// Flat ordered list of every video to show — typically *all* today's
  /// videos across every category (Tips, Avoid, Be Aware).
  final List<FeedEntry> entries;

  /// Index of the entry that was tapped — the page the player opens on.
  final int initialIndex;

  const VideoPlayerScreen({
    super.key,
    required this.entries,
    required this.initialIndex,
  });

  /// Convenience helper for callers that only have one video.
  factory VideoPlayerScreen.single({
    Key? key,
    required VideoItem video,
    required String category,
    bool isRewatch = false,
  }) {
    return VideoPlayerScreen(
      key: key,
      entries: [FeedEntry(video: video, category: category, isRewatch: isRewatch)],
      initialIndex: 0,
    );
  }

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  // Per-index player state.
  final Map<int, BetterPlayerController> _controllers = {};
  final Set<int> _markedWatched = {};

  // Number of pages to keep alive on each side of the current page.
  static const int _keepAliveRadius = 1;

  // True once we've warmed the initial controllers — guards against
  // didChangeDependencies firing multiple times (e.g. MediaQuery changes).
  bool _didFirstWarm = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.entries.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    // NOTE: warming happens in didChangeDependencies because it needs
    // MediaQuery.of(context), which isn't safe to call in initState.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didFirstWarm) {
      _didFirstWarm = true;
      _warmControllersAround(_currentIndex);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      try {
        c.dispose();
      } catch (_) {}
    }
    _controllers.clear();
    _pageController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════
  //  CONTROLLER LIFECYCLE
  // ═══════════════════════════════════════════════════════

  /// Ensure controllers exist for current ± radius and dispose far ones.
  void _warmControllersAround(int index) {
    // Init nearby.
    for (int i = index - _keepAliveRadius; i <= index + _keepAliveRadius; i++) {
      if (i < 0 || i >= widget.entries.length) continue;
      if (_controllers[i] == null) _initController(i, autoPlay: i == index);
    }
    // Dispose anything beyond radius.
    final keep = <int>{
      for (int i = index - _keepAliveRadius;
          i <= index + _keepAliveRadius;
          i++)
        if (i >= 0 && i < widget.entries.length) i,
    };
    final disposable = _controllers.keys.where((k) => !keep.contains(k)).toList();
    for (final k in disposable) {
      _disposeController(k);
    }
  }

  void _initController(int index, {required bool autoPlay}) {
    final entry = widget.entries[index];
    final screenAspect = _screenAspect();

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      entry.video.streamUrl,
      videoFormat: BetterPlayerVideoFormat.hls,
      cacheConfiguration: const BetterPlayerCacheConfiguration(
        useCache: true,
        maxCacheSize: 100 * 1024 * 1024,
        maxCacheFileSize: 20 * 1024 * 1024,
      ),
    );

    final config = BetterPlayerConfiguration(
      aspectRatio: screenAspect,
      fit: BoxFit.cover,
      autoPlay: autoPlay,
      looping: true, // reels loop until user swipes away
      fullScreenByDefault: false,
      allowedScreenSleep: false,
      expandToFill: true,
      handleLifecycle: true,
      controlsConfiguration: const BetterPlayerControlsConfiguration(
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

    final controller = BetterPlayerController(config);
    controller.addEventsListener((event) => _onPlayerEvent(index, event));

    // Fire and forget setup — the page widget shows a spinner while loading.
    controller.setupDataSource(dataSource).then((_) {
      controller.setOverriddenAspectRatio(screenAspect);
      if (mounted) setState(() {});
    }).catchError((e) {
      log('[Reel #$index] setup failed: $e');
    });

    _controllers[index] = controller;
  }

  void _disposeController(int index) {
    final c = _controllers.remove(index);
    if (c != null) {
      try {
        c.dispose();
      } catch (_) {}
    }
  }

  double _screenAspect() {
    final s = MediaQuery.of(context).size;
    return s.width / s.height;
  }

  // ═══════════════════════════════════════════════════════
  //  PLAYER EVENTS
  // ═══════════════════════════════════════════════════════

  void _onPlayerEvent(int index, BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        _selectPreferredAudioTrack(index);
        break;
      case BetterPlayerEventType.progress:
        _checkWatchProgress(index);
        break;
      default:
        break;
    }
  }

  /// Honour `preferred_audio_lang` from the catalog. Native HLS audio
  /// variants are exposed via `betterPlayerAsmsAudioTracks` — we pick the
  /// matching `language` and call `setAudioTrack`. Wrapped in try/catch
  /// because some platform implementations throw if called before tracks
  /// are populated.
  void _selectPreferredAudioTrack(int index) {
    final controller = _controllers[index];
    final entry = widget.entries[index];
    if (controller == null) return;

    final tracks = controller.betterPlayerAsmsAudioTracks;
    if (tracks == null || tracks.isEmpty) {
      log('[Reel #$index] no alternate audio tracks on stream');
      return;
    }

    final preferred = entry.video.preferredAudioLang.toLowerCase();
    BetterPlayerAsmsAudioTrack? pick(String lang) {
      for (final t in tracks) {
        if ((t.language ?? '').toLowerCase() == lang) return t;
      }
      return null;
    }

    final match = pick(preferred) ?? pick('hi') ?? pick('en') ?? tracks.first;
    log('[Reel #$index] audio → ${match.language ?? "?"} (wanted $preferred)');
    try {
      controller.setAudioTrack(match);
    } catch (e) {
      log('[Reel #$index] setAudioTrack ignored: $e');
    }
  }

  void _checkWatchProgress(int index) {
    if (_markedWatched.contains(index)) return;
    final c = _controllers[index];
    final pos = c?.videoPlayerController?.value.position;
    final dur = c?.videoPlayerController?.value.duration;
    if (pos == null || dur == null || dur.inSeconds == 0) return;
    if (pos.inSeconds / dur.inSeconds >= VirtualHelpConfig.watchThreshold) {
      _markedWatched.add(index);
      final entry = widget.entries[index];
      log('[Reel #$index] marking watched: ${entry.video.id}');
      context
          .read<VirtualHelpProvider>()
          .markVideoWatched(entry.video.id, entry.category);
    }
  }

  // ═══════════════════════════════════════════════════════
  //  PAGE CHANGE
  // ═══════════════════════════════════════════════════════

  void _onPageChanged(int newIndex) {
    final oldIndex = _currentIndex;
    _currentIndex = newIndex;

    // Pause the page we left.
    _controllers[oldIndex]?.pause();

    // Play (or schedule play after setup) the new page.
    final newCtrl = _controllers[newIndex];
    if (newCtrl != null) {
      newCtrl.play();
    }

    // Warm neighbours / dispose strangers.
    _warmControllersAround(newIndex);
    setState(() {});
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
          // ── Vertical Reels-style swipe ───────────────────────────────
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.entries.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              return _ReelPage(
                entry: widget.entries[index],
                controller: _controllers[index],
              );
            },
          ),

          // ── Back button (overlays every reel) ────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _ReelTopBar(
              category: widget.entries[_currentIndex].category,
              position: _currentIndex + 1,
              total: widget.entries.length,
              onBack: () {
                SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
//  REEL PAGE — a single full-screen video + metadata overlay
// ═════════════════════════════════════════════════════════════════════

class _ReelPage extends StatelessWidget {
  final FeedEntry entry;
  final BetterPlayerController? controller;

  const _ReelPage({required this.entry, required this.controller});

  Color get _accent =>
      VirtualHelpTheme.categoryAccent[entry.category] ?? VirtualHelpTheme.brand;

  String get _categoryLabel =>
      VirtualHelpTheme.categoryLabel[entry.category] ??
      entry.category.toUpperCase();

  @override
  Widget build(BuildContext context) {
    final isReady =
        controller != null && (controller!.isVideoInitialized() ?? false);

    return Stack(
      children: [
        // ── Ambient gradient (visible briefly while video buffers) ─────
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

        // ── The video itself, edge-to-edge ───────────────────────────
        if (isReady)
          Positioned.fill(
            child: ClipRect(
              child: SizedBox.expand(
                child: BetterPlayer(controller: controller!),
              ),
            ),
          )
        else
          const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          ),

        // ── Bottom metadata (category pill, title, description, progress) ─
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _ReelBottomOverlay(
            entry: entry,
            accent: _accent,
            categoryLabel: _categoryLabel,
            controller: controller,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
//  TOP BAR — only a back button + tiny category/position label
// ═════════════════════════════════════════════════════════════════════

class _ReelTopBar extends StatelessWidget {
  final String category;
  final int position;
  final int total;
  final VoidCallback onBack;

  const _ReelTopBar({
    required this.category,
    required this.position,
    required this.total,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final categoryLabel =
        VirtualHelpTheme.categoryLabel[category] ?? category.toUpperCase();
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top + 14, 20, 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.35),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: const Icon(Icons.chevron_left_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
          const Spacer(),
          Text(
            'Virtual Help · $categoryLabel',
            style: VirtualHelpTheme.sans(
              size: 10,
              weight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.78),
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$position / $total',
              style: VirtualHelpTheme.sans(
                size: 10,
                weight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
//  BOTTOM OVERLAY — pill, title, description, progress
// ═════════════════════════════════════════════════════════════════════

class _ReelBottomOverlay extends StatelessWidget {
  final FeedEntry entry;
  final Color accent;
  final String categoryLabel;
  final BetterPlayerController? controller;

  const _ReelBottomOverlay({
    required this.entry,
    required this.accent,
    required this.categoryLabel,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 60, 20, bottom + 24),
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
            entry.video.title,
            style: VirtualHelpTheme.serif(
              size: 20,
              weight: FontWeight.w200,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),

          // Description
          Text(
            entry.video.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: VirtualHelpTheme.sans(
              size: 11,
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),

          // Progress bar
          _ReelProgressBar(controller: controller),

          const SizedBox(height: 6),
          // Hint text for swipe gesture (only on first 1-2 reels in session
          // a UX nicety; cheaply implemented by always showing it small).
          Center(
            child: Text(
              'Swipe up for next ·',
              style: VirtualHelpTheme.sans(
                size: 9,
                weight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.4),
                letterSpacing: 0.06,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelProgressBar extends StatefulWidget {
  final BetterPlayerController? controller;
  const _ReelProgressBar({this.controller});

  @override
  State<_ReelProgressBar> createState() => _ReelProgressBarState();
}

class _ReelProgressBarState extends State<_ReelProgressBar> {
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?.addEventsListener(_onEvent);
  }

  @override
  void didUpdateWidget(covariant _ReelProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeEventsListener(_onEvent);
      widget.controller?.addEventsListener(_onEvent);
    }
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
