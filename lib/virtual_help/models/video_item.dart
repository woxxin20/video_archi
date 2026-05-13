/// Represents a single video entry from server catalog.
class VideoItem {
  final String id;
  final String fullId;
  final String title;
  final String description;
  final int durationSec;
  final String streamUrl; // HLS master.m3u8 URL
  final String thumbnailUrl;
  final String preferredAudioLang; // Server-recommended audio language
  final List<String> availableAudioLangs; // All available audio tracks
  final String videoLangResolved; // Resolved audio language (for compatibility)
  final bool active;

  const VideoItem({
    required this.id,
    required this.fullId,
    required this.title,
    required this.description,
    required this.durationSec,
    required this.streamUrl,
    required this.thumbnailUrl,
    required this.preferredAudioLang,
    required this.availableAudioLangs,
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
      streamUrl: json['stream_url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String,
      preferredAudioLang: json['preferred_audio_lang'] as String,
      availableAudioLangs: List<String>.from(
        json['available_audio_langs'] ?? ['en'],
      ),
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
    'stream_url': streamUrl,
    'thumbnail_url': thumbnailUrl,
    'preferred_audio_lang': preferredAudioLang,
    'available_audio_langs': availableAudioLangs,
    'video_lang_resolved': videoLangResolved,
    'active': active,
  };
}
