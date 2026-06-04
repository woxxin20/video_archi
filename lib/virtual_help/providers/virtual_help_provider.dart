import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../config.dart';
import '../models/catalog_response.dart';
import '../models/category_state.dart';
import '../models/video_item.dart';
import '../database/database_service.dart';
import '../services/api_service.dart';
import '../services/install_id_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/video_preload_service.dart';

/// Represents what to show for a single slot in the feed.
class FeedSlot {
  final VideoItem video;
  final bool isRewatch;
  const FeedSlot({required this.video, required this.isRewatch});
}

/// Main provider that orchestrates all Virtual Help logic.
///
/// Implements every section of the architecture:
/// - Mode switching (Section 15)
/// - Language changing (Section 16)
/// - Catalog fetching & caching (Sections 6-9)
/// - Queue management (Sections 10, 12)
/// - Video selection (Section 19)
/// - Watch progress marking (Section 13)
/// - Category reset (Section 18)
/// - New video sync (Section 17)
/// - Offline handling (Section 23)
class VirtualHelpProvider extends ChangeNotifier {
  final ApiService _api;
  final DatabaseService _db;
  final VideoPreloadService _preloadService = VideoPreloadService();

  // ─── Core State ───
  String _installId = '';
  String _currentMode = VirtualHelpConfig.defaultMode;
  String _currentLang = VirtualHelpConfig.defaultLang;
  LocalState _localState = LocalState.empty();

  // Stored catalog per mode (only current mode's catalog is typically loaded)
  final Map<String, CatalogResponse> _catalogs = {};

  // Stored catalog versions
  String _catalogVersionPeriod = '';
  String _catalogVersionPregnancy = '';

  // Loading / error states
  bool _isLoading = true;
  bool _isOnline = true;
  String? _errorMessage;
  bool _isInitialized = false;

  // ─── Getters ───
  String get currentMode => _currentMode;
  String get currentLang => _currentLang;
  String get installId => _installId;
  bool get isLoading => _isLoading;
  bool get isOnline => _isOnline;
  String? get errorMessage => _errorMessage;
  bool get isInitialized => _isInitialized;
  CatalogResponse? get currentCatalog => _catalogs[_currentMode];
  LocalState get localState => _localState;
  VideoPreloadService get preloadService => _preloadService;

  VirtualHelpProvider({ApiService? api, DatabaseService? db})
    : _api = api ?? ApiService(),
      _db = db ?? DatabaseService.instance;

  // ═══════════════════════════════════════════════════════
  //  INITIALIZATION (Section 14 — First Install + Subsequent Opens)
  // ═══════════════════════════════════════════════════════

  /// Full initialization flow. Call once from app startup.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Get or create install ID
      _installId = await InstallIdService.getOrCreate();

      // 2. Load persisted preferences
      final prefs = await SharedPreferences.getInstance();
      _currentMode =
          prefs.getString('vh_current_mode') ?? VirtualHelpConfig.defaultMode;
      _currentLang =
          prefs.getString('vh_current_lang') ?? VirtualHelpConfig.defaultLang;
      _catalogVersionPeriod =
          prefs.getString('vh_catalog_version_period') ?? '';
      _catalogVersionPregnancy =
          prefs.getString('vh_catalog_version_pregnancy') ?? '';

      // 3. Initialize database
      await _db.initialize();

      // 4. Load local state from Isar
      try {
        final stateJson = await _db.loadLocalState();
        if (stateJson != null) {
          _localState = LocalState.fromJson(stateJson);
        }
      } catch (e) {
        debugPrint('Corrupted local state, resetting: $e');
        _localState = LocalState.empty();
        await _db.storeLocalState(_localState.toJson());
      }

      // 5. Check connectivity
      final connectivity = await Connectivity().checkConnectivity();
      _isOnline = !connectivity.contains(ConnectivityResult.none);

      // 6. Load stored catalog for current mode
      await _loadStoredCatalog(_currentMode);

      // 7. If online, check catalog version and sync
      if (_isOnline) {
        await _checkAndSyncCatalog(_currentMode);
      }

      // 8. Trigger preloading for Tips slot 1 (Section 14)
      _triggerPreload();

      // 9. If no catalog at all (first launch offline), show error
      //    (Preserve any specific error already set by _checkAndSyncCatalog.)
      if (_catalogs[_currentMode] == null && _errorMessage == null) {
        _errorMessage = _isOnline
            ? 'Server unreachable at ${VirtualHelpConfig.serverBaseUrl}'
            : 'Connect to internet to load your content.';
      }

      _isInitialized = true;
    } catch (e) {
      _errorMessage = 'Initialization failed: $e';
      debugPrint('VirtualHelpProvider init error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Retry initialization (for offline first-launch retry button).
  Future<void> retry() async {
    _isInitialized = false;
    await initialize();
  }

  // ═══════════════════════════════════════════════════════
  //  CATALOG LOADING & SYNCING (Sections 6, 7, 9, 17)
  // ═══════════════════════════════════════════════════════

  Future<void> _loadStoredCatalog(String mode) async {
    final json = await _db.loadCatalog(mode, _currentLang);
    if (json == null) return;
    try {
      final cached = CatalogResponse.fromJson(json);

      // Schema-drift guard: if cached stream_urls still go through the legacy
      // /hls/ proxy endpoint (which has been removed in favour of pointing
      // straight at the CDN's native master.m3u8), drop the cache so the
      // device re-fetches with the correct direct-CDN URLs.
      String? sampleStreamUrl;
      for (final c in cached.categories.values) {
        for (final v in c.videos) {
          if (v.streamUrl.isNotEmpty) {
            sampleStreamUrl = v.streamUrl;
            break;
          }
        }
        if (sampleStreamUrl != null) break;
      }
      if (sampleStreamUrl != null && sampleStreamUrl.contains('/hls/')) {
        debugPrint(
            '[Provider] Cached catalog uses legacy /hls/ endpoint, invalidating');
        await _db.deleteCatalog(mode, _currentLang);
        // Also reset stored version so next sync re-fetches
        final prefs = await SharedPreferences.getInstance();
        if (mode == 'period') {
          _catalogVersionPeriod = '';
          await prefs.setString('vh_catalog_version_period', '');
        } else {
          _catalogVersionPregnancy = '';
          await prefs.setString('vh_catalog_version_pregnancy', '');
        }
        return;
      }

      _catalogs[mode] = cached;
    } catch (e) {
      // Corrupted catalog — delete and re-fetch (Section 22)
      debugPrint('Corrupted catalog for $mode, deleting: $e');
      await _db.deleteCatalog(mode, _currentLang);
    }
  }

  Future<void> _checkAndSyncCatalog(String mode) async {
    final storedVersion = mode == 'period'
        ? _catalogVersionPeriod
        : _catalogVersionPregnancy;

    debugPrint(
        '[Provider] Sync $mode (lang=$_currentLang) from ${VirtualHelpConfig.serverBaseUrl}');

    // Lightweight version check (Section 14)
    final versionResult = await _api.fetchCatalogVersion(mode);
    if (!versionResult.isOk) {
      if (_catalogs[mode] == null) _errorMessage = versionResult.error;
      return;
    }
    final serverVersion = versionResult.data!;

    if (storedVersion == serverVersion && _catalogs.containsKey(mode)) {
      // Same version, use cached — zero additional network call
      return;
    }

    // Version changed or no catalog stored — fetch full catalog
    final catalogResult = await _api.fetchCatalog(mode, _currentLang);
    if (!catalogResult.isOk) {
      if (_catalogs[mode] == null) _errorMessage = catalogResult.error;
      return;
    }
    final catalogJson = catalogResult.data!;

    final CatalogResponse catalog;
    try {
      catalog = CatalogResponse.fromJson(catalogJson);
    } catch (e) {
      _errorMessage = 'Catalog parse failed: $e';
      debugPrint('[Provider] Catalog parse error: $e');
      return;
    }
    _catalogs[mode] = catalog;
    debugPrint(
        '[Provider] Catalog loaded: $mode/$_currentLang v${catalog.catalogVersion}');

    // Store in Isar
    await _db.storeCatalog(mode, _currentLang, catalogJson);

    // Update stored version
    final prefs = await SharedPreferences.getInstance();
    if (mode == 'period') {
      _catalogVersionPeriod = catalog.catalogVersion;
      await prefs.setString(
        'vh_catalog_version_period',
        catalog.catalogVersion,
      );
    } else {
      _catalogVersionPregnancy = catalog.catalogVersion;
      await prefs.setString(
        'vh_catalog_version_pregnancy',
        catalog.catalogVersion,
      );
    }

    // Sync new videos into queues (Section 17)
    final modeState = _localState.modeStates.putIfAbsent(mode, () => {});
    if (modeState.isEmpty) {
      // First time for this mode — initialize queues
      CatalogSyncService.initializeQueues(
        catalog: catalog,
        modeState: modeState,
        installId: _installId,
      );
    } else {
      // Existing state — sync any new videos
      CatalogSyncService.syncNewVideos(
        catalog: catalog,
        modeState: modeState,
        mode: mode,
      );
    }

    await _saveLocalState();
    if (mode == _currentMode) {
      _triggerPreload();
    }
  }

  /// Section 14: Pre-initialize video controller for queue[0] of Tips (slot 1 only)
  void _triggerPreload() {
    final catalog = _catalogs[_currentMode];
    if (catalog == null) return;

    final tipsState = _localState.getState(_currentMode, 'tips');
    if (tipsState.unwatchedQueue.isNotEmpty) {
      final firstId = tipsState.unwatchedQueue.first;
      final video = catalog.findVideo('tips', firstId);
      if (video != null) {
        _preloadService.preloadVideo(video);
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  //  VIDEO SELECTION (Section 19 — Per-Open Stability)
  // ═══════════════════════════════════════════════════════

  /// Get the feed slots for a given category in the current mode.
  /// Returns up to 2 FeedSlots based on the selection algorithm.
  List<FeedSlot> getFeedForCategory(String category) {
    final catalog = _catalogs[_currentMode];
    if (catalog == null) return [];

    final catState = _localState.getState(_currentMode, category);
    final slots = <FeedSlot>[];

    if (catState.unwatchedQueue.isEmpty && catState.watched.isEmpty) {
      return []; // No data yet
    }

    final queueLen = catState.unwatchedQueue.length;

    if (queueLen >= 2) {
      // Normal case: show first 2 unwatched
      final v1 = catalog.findVideo(category, catState.unwatchedQueue[0]);
      final v2 = catalog.findVideo(category, catState.unwatchedQueue[1]);
      if (v1 != null) slots.add(FeedSlot(video: v1, isRewatch: false));
      if (v2 != null) slots.add(FeedSlot(video: v2, isRewatch: false));
    } else if (queueLen == 1) {
      // 1 unwatched + oldest watched as rewatch
      final v1 = catalog.findVideo(category, catState.unwatchedQueue[0]);
      if (v1 != null) slots.add(FeedSlot(video: v1, isRewatch: false));

      if (catState.watched.isNotEmpty) {
        final rewatchId = catState.watched.first;
        final v2 = catalog.findVideo(category, rewatchId);
        if (v2 != null) slots.add(FeedSlot(video: v2, isRewatch: true));
      }
    } else {
      // Queue is 0 — should have been reset. Show from watched as fallback.
      for (int i = 0; i < catState.watched.length && slots.length < 2; i++) {
        final v = catalog.findVideo(category, catState.watched[i]);
        if (v != null) slots.add(FeedSlot(video: v, isRewatch: true));
      }
    }

    return slots;
  }

  // ═══════════════════════════════════════════════════════
  //  WATCH PROGRESS (Section 13)
  // ═══════════════════════════════════════════════════════

  /// Mark a video as watched. Moves from unwatched_queue to watched.
  /// Triggers category reset if queue becomes empty.
  Future<void> markVideoWatched(String videoId, String category) async {
    final catState = _localState.getState(_currentMode, category);

    // Duplicate guard (Section 14, 22)
    if (catState.watched.contains(videoId)) return;

    // Move from queue to watched
    catState.unwatchedQueue.remove(videoId);
    catState.watched.add(videoId);

    // Check if category needs reset (Section 18)
    if (catState.unwatchedQueue.isEmpty) {
      final catalog = _catalogs[_currentMode];
      if (catalog != null) {
        final allActiveIds = catalog.activeIdsForCategory(category);
        CatalogSyncService.resetCategory(
          catState: catState,
          allActiveIds: allActiveIds,
          installId: _installId,
        );
      }
    }

    await _saveLocalState();
    _triggerPreload();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  //  MODE SWITCHING (Section 15)
  // ═══════════════════════════════════════════════════════

  /// Switch between period and pregnancy modes.
  /// Does NOT clear the other mode's state or catalog.
  Future<void> switchMode(String newMode) async {
    if (newMode == _currentMode) return;
    if (!VirtualHelpConfig.validModes.contains(newMode)) return;

    _currentMode = newMode;
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vh_current_mode', newMode);

    // Load catalog for new mode if not already loaded
    if (!_catalogs.containsKey(newMode)) {
      await _loadStoredCatalog(newMode);
    }

    // If online and catalog needs sync
    if (_isOnline) {
      await _checkAndSyncCatalog(newMode);
    }

    // If still no catalog (first time for this mode, offline)
    if (_catalogs[newMode] == null) {
      _errorMessage = 'Connect to internet to load content for this mode.';
    } else {
      _errorMessage = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  //  LANGUAGE CHANGE (Section 16)
  // ═══════════════════════════════════════════════════════

  /// Change the active language. Invalidates all stored catalogs.
  /// Watch history is PRESERVED (IDs are language-agnostic).
  Future<void> changeLanguage(String newLang) async {
    if (newLang == _currentLang) return;

    _isLoading = true;
    _currentLang = newLang;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vh_current_lang', newLang);

    // Delete all stored catalogs (old language versions are stale)
    await _db.deleteAllCatalogs();
    _catalogs.clear();

    // Reset stored catalog versions to force re-fetch
    _catalogVersionPeriod = '';
    _catalogVersionPregnancy = '';
    await prefs.setString('vh_catalog_version_period', '');
    await prefs.setString('vh_catalog_version_pregnancy', '');

    // Immediately fetch catalog for current mode in new language
    if (_isOnline) {
      await _checkAndSyncCatalog(_currentMode);
    }

    if (_catalogs[_currentMode] == null) {
      _errorMessage = 'Connect to internet to load content in new language.';
    } else {
      _errorMessage = null;
    }

    _isLoading = false;
    _triggerPreload();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  //  CONNECTIVITY (Section 23)
  // ═══════════════════════════════════════════════════════

  /// Update online status. Optionally trigger a catalog sync on reconnect.
  Future<void> updateConnectivity(List<ConnectivityResult> results) async {
    final wasOffline = !_isOnline;
    _isOnline = !results.contains(ConnectivityResult.none);

    if (_isOnline && wasOffline && _isInitialized) {
      // Just came online — run catalog version check
      await _checkAndSyncCatalog(_currentMode);
      if (_catalogs[_currentMode] != null) {
        _errorMessage = null;
      }
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════
  //  PERSISTENCE
  // ═══════════════════════════════════════════════════════

  Future<void> _saveLocalState() async {
    await _db.storeLocalState(_localState.toJson());
  }

  // ═══════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════

  /// Get all categories for the current mode's catalog.
  List<String> get currentCategories {
    return _catalogs[_currentMode]?.categories.keys.toList() ??
        VirtualHelpConfig.validCategories;
  }

  /// Lookup a video by ID in the current catalog.
  VideoItem? lookupVideo(String category, String videoId) {
    return _catalogs[_currentMode]?.findVideo(category, videoId);
  }

  @override
  void dispose() {
    _api.dispose();
    _preloadService.dispose();
    super.dispose();
  }
}
