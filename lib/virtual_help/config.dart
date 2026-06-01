/// Central configuration for the Virtual Help module.
/// Change [serverBaseUrl] before initializing in your app.
class VirtualHelpConfig {
  /// Base URL of the catalog server (no trailing slash).
  /// The server returns `stream_url`/`thumbnail_url` already pointed at the CDN
  /// (configured server-side), so this only governs API endpoints.
  /// Defaults to the LAN host where the production server runs (CDN: http://192.168.1.57/videos/).
  static String serverBaseUrl = 'http://192.168.1.57:8080';

  /// A video is "watched" once this fraction of its duration has been played.
  static const double watchThreshold = 0.70;

  /// How many unwatched videos to show per category in the feed.
  static const int videosPerCategory = 2;

  /// Default language code used on first install.
  static const String defaultLang = 'en';

  /// Default mode on first install.
  static const String defaultMode = 'period';

  /// Valid modes.
  static const List<String> validModes = ['period', 'pregnancy'];

  /// Valid categories (same for both modes).
  static const List<String> validCategories = ['tips', 'awareness', 'avoid'];

  /// All 25 supported language codes.
  static const List<String> supportedLanguages = [
    'en', 'hi', 'af', 'am', 'ar', 'bn', 'de', 'es', 'fa', 'fr',
    'id', 'it', 'ja', 'ko', 'pa', 'pt', 'ru', 'sw', 'ta', 'tl',
    'th', 'tr', 'ur', 'vi', 'zh',
  ];
}
