import 'dart:math';

/// Deterministic seeded shuffle (Fisher-Yates) for video queue generation.
/// Same installId + same cycle = same order.
/// Different devices = different order.
class ShuffleService {
  /// Generate a deterministically shuffled queue of video IDs.
  ///
  /// [videoIds] — list of all video IDs in the category.
  /// [installId] — device's unique install UUID.
  /// [cycle] — current cycle number (increments on category reset).
  static List<String> generateShuffledQueue({
    required List<String> videoIds,
    required String installId,
    required int cycle,
  }) {
    // Combine installId hash and cycle number as seed
    final seed = installId.hashCode ^ cycle.hashCode;
    final rng = Random(seed);
    final shuffled = List<String>.from(videoIds);

    // Fisher-Yates shuffle
    for (int i = shuffled.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final temp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = temp;
    }

    return shuffled;
  }
}
