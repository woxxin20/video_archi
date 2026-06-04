import 'video_item.dart';

/// One slot in the flattened "today" feed shown to the user.
/// Pairs a video with the category it came from so the player can render
/// the correct category pill on each reel without re-querying state.
class FeedEntry {
  final VideoItem video;
  final String category;
  final bool isRewatch;

  const FeedEntry({
    required this.video,
    required this.category,
    required this.isRewatch,
  });
}
