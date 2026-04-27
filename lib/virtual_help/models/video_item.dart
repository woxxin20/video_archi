/// Represents a single video entry from the server catalog.
class VideoItem {
  final String id;
  final String fullId;
  final String title;
  final String description;
  final int durationSec;
  final String videoUrl;
  final String thumbnailUrl;
  final String videoLangResolved;
  final bool active;

  const VideoItem({
    required this.id,
    required this.fullId,
    required this.title,
    required this.description,
    required this.durationSec,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.videoLangResolved,
    this.active = true,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      id: json['id'] as String,
      fullId: json['full_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      durationSec: json['duration_sec'] as int,
      videoUrl: json['video_url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String,
      videoLangResolved: json['video_lang_resolved'] as String,
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_id': fullId,
        'title': title,
        'description': description,
        'duration_sec': durationSec,
        'video_url': videoUrl,
        'thumbnail_url': thumbnailUrl,
        'video_lang_resolved': videoLangResolved,
        'active': active,
      };
}
