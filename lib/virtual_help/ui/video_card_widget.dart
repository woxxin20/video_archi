import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/video_item.dart';
import 'virtual_help_theme.dart';

/// Badge type to show on a video card.
enum VHBadgeType { today, done, category }

/// Portrait-style video card matching the Virtual Help design.
/// Width: 128 px. Thumbnail height: 210 px.
class VideoCardWidget extends StatelessWidget {
  final VideoItem video;

  /// Whether this video has already been watched (dims the card).
  final bool isRewatch;

  /// Server-side category key, e.g. 'tips', 'avoid', 'awareness'.
  final String category;

  /// Show the "Watch Now" + TODAY badge (first unwatched in feed).
  final bool isToday;

  /// Called when the card is tapped. The parent owns navigation so it can
  /// build the cross-category "all of today" reel list before pushing.
  final VoidCallback onTap;

  const VideoCardWidget({
    super.key,
    required this.video,
    required this.isRewatch,
    required this.category,
    required this.onTap,
    this.isToday = false,
  });

  Color get _accent =>
      VirtualHelpTheme.categoryAccent[category] ?? VirtualHelpTheme.brand;

  List<Color> get _gradientColors =>
      VirtualHelpTheme.categoryGradient[category] ??
      [const Color(0xFFFFDCB8), const Color(0xFFFF8C42)];

  String get _badgeLabel {
    if (isRewatch) return 'DONE';
    if (isToday) return 'TODAY';
    if (category == 'avoid') return 'AVOID';
    if (category == 'awareness') return 'AWARE';
    return 'NEW';
  }

  Color get _badgeColor {
    if (isRewatch) return Colors.black.withValues(alpha: 0.35);
    return _accent;
  }

  String get _categoryLabel =>
      VirtualHelpTheme.categoryLabel[category] ?? category.toUpperCase();

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isRewatch ? 0.5 : 1.0,
        child: Container(
          width: VirtualHelpTheme.cardWidth,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              VirtualHelpTheme.cardBorderRadius,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x21784614),
                blurRadius: 18,
                offset: Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Thumbnail(
                video: video,
                accent: _accent,
                gradientColors: _gradientColors,
                badgeLabel: _badgeLabel,
                badgeColor: _badgeColor,
                isToday: isToday,
                isRewatch: isRewatch,
                duration: _formatDuration(video.durationSec),
              ),
              _InfoRow(
                accent: _accent,
                categoryLabel: _categoryLabel,
                title: video.title,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Thumbnail section ────────────────────────────────────────────────

class _Thumbnail extends StatelessWidget {
  final VideoItem video;
  final Color accent;
  final List<Color> gradientColors;
  final String badgeLabel;
  final Color badgeColor;
  final bool isToday;
  final bool isRewatch;
  final String duration;

  const _Thumbnail({
    required this.video,
    required this.accent,
    required this.gradientColors,
    required this.badgeLabel,
    required this.badgeColor,
    required this.isToday,
    required this.isRewatch,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: VirtualHelpTheme.cardWidth,
      height: VirtualHelpTheme.cardThumbnailHeight,
      child: Stack(
        children: [
          // Gradient background
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-0.6, -0.8),
                  end: const Alignment(0.6, 0.8),
                  colors: gradientColors,
                ),
              ),
            ),
          ),

          // Network thumbnail (if available)
          if (video.thumbnailUrl.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: video.thumbnailUrl,
                fit: BoxFit.cover,
                errorWidget: (_, $1, $2) => const SizedBox.shrink(),
              ),
            ),

          // Bottom scrim
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: const [0, 0.55],
                  colors: [
                    Colors.black.withValues(alpha: 0.48),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Badge (top-left)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badgeLabel,
                style: VirtualHelpTheme.sans(
                  size: 8,
                  weight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: isRewatch ? 0.7 : 1.0),
                  letterSpacing: 0.08,
                ),
              ),
            ),
          ),

          // Duration (top-right)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                duration,
                style: VirtualHelpTheme.sans(
                  size: 8,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // Silhouette icon
          Center(
            child: Opacity(
              opacity: 0.2,
              child: Icon(Icons.person, color: Colors.white, size: 48),
            ),
          ),

          // "Watch Now" strip (today only)
          if (isToday)
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: VirtualHelpTheme.brand.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '▶ Watch Now',
                    style: VirtualHelpTheme.sans(
                      size: 8,
                      weight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.06,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Info row below thumbnail ─────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final Color accent;
  final String categoryLabel;
  final String title;

  const _InfoRow({
    required this.accent,
    required this.categoryLabel,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: VirtualHelpTheme.cardWidth,
      color: VirtualHelpTheme.bgWhite,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            categoryLabel == 'Tips' ? 'Daily Tip' : categoryLabel,
            style: VirtualHelpTheme.sans(
              size: 8,
              weight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.10,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: VirtualHelpTheme.sans(
              size: 10.5,
              weight: FontWeight.w600,
              color: VirtualHelpTheme.textPrimary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
