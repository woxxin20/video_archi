// Unit tests for the Virtual Help architecture's queue/shuffle/sync logic.
// These do NOT exercise UI, network, or storage — they verify the pure
// algorithms that govern user-facing video selection so future refactors
// cannot break the spec's invariants from VirtualHelp_HLS_Architecture.md.

import 'package:flutter_test/flutter_test.dart';

import 'package:video_archi/virtual_help/models/catalog_response.dart';
import 'package:video_archi/virtual_help/models/category_state.dart';
import 'package:video_archi/virtual_help/services/catalog_sync_service.dart';
import 'package:video_archi/virtual_help/services/shuffle_service.dart';

CatalogResponse _catalog({
  required Map<String, List<String>> categoriesIds,
  String mode = 'period',
  String version = 'v1',
}) {
  final categories = <String, dynamic>{};
  for (final entry in categoriesIds.entries) {
    categories[entry.key] = {
      'total': entry.value.length,
      'videos': [
        for (final id in entry.value)
          {
            'id': id,
            'full_id': '$mode/${entry.key}/$id',
            'title': 'Title $id',
            'description': 'Desc $id',
            'duration_sec': 60,
            'stream_url': 'http://192.168.1.57/videos/$mode/${entry.key}/$id/master.m3u8',
            'thumbnail_url': 'http://192.168.1.57/videos/$mode/${entry.key}/$id/Thumbnail.webp',
            'preferred_audio_lang': 'en',
            'available_audio_langs': ['en'],
            'video_lang_resolved': 'en',
            'active': true,
          },
      ],
    };
  }
  return CatalogResponse.fromJson({
    'mode': mode,
    'lang': 'en',
    'lang_resolved': 'en',
    'catalog_version': version,
    'categories': categories,
  });
}

void main() {
  group('ShuffleService — deterministic seeded shuffle', () {
    test('same installId + same cycle → same order', () {
      final ids = ['001', '002', '003', '004', '005', '006', '007'];
      final a = ShuffleService.generateShuffledQueue(
          videoIds: ids, installId: 'install-a', cycle: 1);
      final b = ShuffleService.generateShuffledQueue(
          videoIds: ids, installId: 'install-a', cycle: 1);
      expect(a, equals(b));
    });

    test('different installId → likely different order', () {
      final ids = ['001', '002', '003', '004', '005', '006', '007'];
      final a = ShuffleService.generateShuffledQueue(
          videoIds: ids, installId: 'install-a', cycle: 1);
      final b = ShuffleService.generateShuffledQueue(
          videoIds: ids, installId: 'install-different', cycle: 1);
      expect(a, isNot(equals(b)));
    });

    test('next cycle reshuffles', () {
      final ids = ['001', '002', '003', '004', '005'];
      final a = ShuffleService.generateShuffledQueue(
          videoIds: ids, installId: 'i', cycle: 1);
      final b = ShuffleService.generateShuffledQueue(
          videoIds: ids, installId: 'i', cycle: 2);
      expect(a, isNot(equals(b)));
    });

    test('shuffled list preserves all IDs exactly once', () {
      final ids = ['001', '002', '003', '004', '005', '006', '007'];
      final shuffled = ShuffleService.generateShuffledQueue(
          videoIds: ids, installId: 'i', cycle: 1);
      expect(shuffled.toSet(), equals(ids.toSet()));
      expect(shuffled.length, equals(ids.length));
    });
  });

  group('CatalogSyncService — initializeQueues (Section 14)', () {
    test('first run populates each category with shuffled queue', () {
      final catalog = _catalog(categoriesIds: {
        'tips': ['001', '002', '003'],
        'awareness': ['001', '002'],
        'avoid': ['001'],
      });
      final modeState = <String, CategoryState>{};

      CatalogSyncService.initializeQueues(
        catalog: catalog,
        modeState: modeState,
        installId: 'install-x',
      );

      expect(modeState['tips']!.unwatchedQueue.length, 3);
      expect(modeState['awareness']!.unwatchedQueue.length, 2);
      expect(modeState['avoid']!.unwatchedQueue.length, 1);
      expect(modeState['tips']!.knownTotal, 3);
    });

    test('does not reshuffle already-populated category', () {
      final catalog = _catalog(categoriesIds: {
        'tips': ['001', '002', '003'],
      });
      final modeState = <String, CategoryState>{
        'tips': CategoryState(
          unwatchedQueue: ['003', '001'],
          watched: ['002'],
          cycle: 1,
          knownTotal: 3,
        ),
      };

      CatalogSyncService.initializeQueues(
        catalog: catalog,
        modeState: modeState,
        installId: 'install-x',
      );

      expect(modeState['tips']!.unwatchedQueue, equals(['003', '001']));
      expect(modeState['tips']!.watched, equals(['002']));
    });
  });

  group('CatalogSyncService — syncNewVideos (Section 17)', () {
    test('appends new IDs to end of queue, preserves watched', () {
      final catalog = _catalog(categoriesIds: {
        'tips': ['001', '002', '003', '004', '005'],
      });
      final modeState = <String, CategoryState>{
        'tips': CategoryState(
          unwatchedQueue: ['002', '003'],
          watched: ['001'],
          cycle: 1,
          knownTotal: 3,
        ),
      };

      final hasNew = CatalogSyncService.syncNewVideos(
        catalog: catalog,
        modeState: modeState,
        mode: 'period',
      );

      expect(hasNew, isTrue);
      // 004 and 005 are new → appended in catalog order at end
      expect(modeState['tips']!.unwatchedQueue, equals(['002', '003', '004', '005']));
      expect(modeState['tips']!.watched, equals(['001']));
      expect(modeState['tips']!.knownTotal, 5);
    });

    test('returns false when no new videos', () {
      final catalog = _catalog(categoriesIds: {
        'tips': ['001', '002'],
      });
      final modeState = <String, CategoryState>{
        'tips': CategoryState(
          unwatchedQueue: ['002'],
          watched: ['001'],
          cycle: 1,
          knownTotal: 2,
        ),
      };

      final hasNew = CatalogSyncService.syncNewVideos(
        catalog: catalog,
        modeState: modeState,
        mode: 'period',
      );

      expect(hasNew, isFalse);
      expect(modeState['tips']!.unwatchedQueue, equals(['002']));
    });
  });

  group('CatalogSyncService — resetCategory (Section 18)', () {
    test('increments cycle, clears watched, reshuffles', () {
      final catState = CategoryState(
        unwatchedQueue: [],
        watched: ['001', '002', '003'],
        cycle: 1,
        knownTotal: 3,
      );

      CatalogSyncService.resetCategory(
        catState: catState,
        allActiveIds: ['001', '002', '003'],
        installId: 'install-x',
      );

      expect(catState.cycle, 2);
      expect(catState.watched, isEmpty);
      expect(catState.unwatchedQueue.length, 3);
      expect(catState.unwatchedQueue.toSet(), equals({'001', '002', '003'}));
    });
  });

  group('CatalogResponse', () {
    test('findVideo returns active video by id', () {
      final catalog = _catalog(categoriesIds: {
        'tips': ['001', '002'],
      });
      final v = catalog.findVideo('tips', '002');
      expect(v, isNotNull);
      expect(v!.id, '002');
    });

    test('findVideo returns null for unknown id', () {
      final catalog = _catalog(categoriesIds: {
        'tips': ['001'],
      });
      expect(catalog.findVideo('tips', '999'), isNull);
    });

    test('activeIdsForCategory lists only active videos', () {
      final catalog = _catalog(categoriesIds: {
        'tips': ['001', '002'],
      });
      expect(catalog.activeIdsForCategory('tips'), equals(['001', '002']));
    });
  });

  group('LocalState — JSON round-trip', () {
    test('preserves all fields through encode/decode', () {
      final original = LocalState(modeStates: {
        'period': {
          'tips': CategoryState(
            unwatchedQueue: ['002', '003'],
            watched: ['001'],
            cycle: 1,
            knownTotal: 3,
          ),
        },
        'pregnancy': {
          'avoid': CategoryState(
            unwatchedQueue: ['001'],
            watched: [],
            cycle: 1,
            knownTotal: 1,
          ),
        },
      });

      final json = original.toJson();
      final restored = LocalState.fromJson(json);

      expect(restored.getState('period', 'tips').unwatchedQueue,
          equals(['002', '003']));
      expect(restored.getState('period', 'tips').watched, equals(['001']));
      expect(restored.getState('pregnancy', 'avoid').unwatchedQueue,
          equals(['001']));
    });
  });
}
