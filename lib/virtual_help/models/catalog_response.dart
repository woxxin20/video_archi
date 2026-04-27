import 'video_item.dart';

/// Represents a single category's data inside the catalog response.
class CategoryCatalog {
  final int total;
  final List<VideoItem> videos;

  const CategoryCatalog({required this.total, required this.videos});

  factory CategoryCatalog.fromJson(Map<String, dynamic> json) {
    return CategoryCatalog(
      total: json['total'] as int,
      videos: (json['videos'] as List)
          .map((v) => VideoItem.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'total': total,
        'videos': videos.map((v) => v.toJson()).toList(),
      };
}

/// Full catalog response from GET /api/catalog.
class CatalogResponse {
  final String mode;
  final String lang;
  final String langResolved;
  final String catalogVersion;
  final Map<String, CategoryCatalog> categories;

  const CatalogResponse({
    required this.mode,
    required this.lang,
    required this.langResolved,
    required this.catalogVersion,
    required this.categories,
  });

  factory CatalogResponse.fromJson(Map<String, dynamic> json) {
    final cats = (json['categories'] as Map<String, dynamic>).map(
      (key, value) =>
          MapEntry(key, CategoryCatalog.fromJson(value as Map<String, dynamic>)),
    );
    return CatalogResponse(
      mode: json['mode'] as String,
      lang: json['lang'] as String,
      langResolved: json['lang_resolved'] as String,
      catalogVersion: json['catalog_version'] as String,
      categories: cats,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'lang': lang,
        'lang_resolved': langResolved,
        'catalog_version': catalogVersion,
        'categories': categories.map((k, v) => MapEntry(k, v.toJson())),
      };

  /// Lookup a video by its short id within a category.
  VideoItem? findVideo(String category, String videoId) {
    final cat = categories[category];
    if (cat == null) return null;
    try {
      return cat.videos.firstWhere(
        (v) => v.id == videoId && v.active,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get all active video IDs for a category.
  List<String> activeIdsForCategory(String category) {
    return categories[category]
            ?.videos
            .where((v) => v.active)
            .map((v) => v.id)
            .toList() ??
        [];
  }
}
