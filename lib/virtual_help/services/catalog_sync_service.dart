import '../models/catalog_response.dart';
import '../models/category_state.dart';
import 'shuffle_service.dart';

/// Handles syncing new videos from a fresh catalog into existing local state.
/// Implements Section 17 of the architecture.
class CatalogSyncService {
  /// Sync new video IDs from catalog into the local state queues.
  ///
  /// For each category, any ID present in the catalog but NOT in
  /// (unwatched_queue + watched) gets appended to the END of unwatched_queue.
  /// Returns true if any new videos were found.
  static bool syncNewVideos({
    required CatalogResponse catalog,
    required Map<String, CategoryState> modeState,
    required String mode,
  }) {
    bool hasNew = false;

    for (final category in catalog.categories.keys) {
      final catState = modeState.putIfAbsent(
        category,
        () => CategoryState.empty(),
      );

      final activeIds = catalog.activeIdsForCategory(category);

      for (final id in activeIds) {
        final alreadyKnown =
            catState.unwatchedQueue.contains(id) || catState.watched.contains(id);
        if (!alreadyKnown) {
          catState.unwatchedQueue.add(id);
          hasNew = true;
        }
      }

      catState.knownTotal = activeIds.length;
    }

    return hasNew;
  }

  /// Initialize queues for a mode being set up for the first time.
  /// Generates shuffled queues for each category.
  static void initializeQueues({
    required CatalogResponse catalog,
    required Map<String, CategoryState> modeState,
    required String installId,
  }) {
    for (final category in catalog.categories.keys) {
      final activeIds = catalog.activeIdsForCategory(category);
      final catState = modeState.putIfAbsent(
        category,
        () => CategoryState.empty(),
      );

      // Only initialize if the queue is empty and nothing is watched
      if (catState.unwatchedQueue.isEmpty && catState.watched.isEmpty) {
        catState.unwatchedQueue = ShuffleService.generateShuffledQueue(
          videoIds: activeIds,
          installId: installId,
          cycle: catState.cycle,
        );
        catState.knownTotal = activeIds.length;
      }
    }
  }

  /// Reset a category: increment cycle, reshuffle all IDs, clear watched.
  /// Called when unwatched_queue reaches empty (Section 18).
  static void resetCategory({
    required CategoryState catState,
    required List<String> allActiveIds,
    required String installId,
  }) {
    catState.cycle += 1;
    catState.unwatchedQueue = ShuffleService.generateShuffledQueue(
      videoIds: allActiveIds,
      installId: installId,
      cycle: catState.cycle,
    );
    catState.watched = [];
  }
}
