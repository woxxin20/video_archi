import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'collections.dart';

/// Handles all Isar database operations for catalog and state persistence.
class DatabaseService {
  static DatabaseService? _instance;
  late Isar _isar;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  bool _initialized = false;

  /// Initialize Isar. Call once at app startup.
  Future<void> initialize() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [CatalogEntrySchema, StateEntrySchema],
      directory: dir.path,
      name: 'virtual_help',
    );
    _initialized = true;
  }

  // ─── Catalog Operations ───

  /// Store catalog JSON for a given mode+lang combo.
  /// Key format: "catalog_{mode}_{lang}"
  Future<void> storeCatalog(String mode, String lang, Map<String, dynamic> catalogJson) async {
    final key = 'catalog_${mode}_$lang';
    final entry = CatalogEntry()
      ..key = key
      ..jsonData = jsonEncode(catalogJson);
    await _isar.writeTxn(() async {
      await _isar.catalogEntrys.putByKey(entry);
    });
  }

  /// Load catalog JSON for a given mode+lang. Returns null if not stored.
  Future<Map<String, dynamic>?> loadCatalog(String mode, String lang) async {
    final key = 'catalog_${mode}_$lang';
    final entry = await _isar.catalogEntrys.where().keyEqualTo(key).findFirst();
    if (entry == null) return null;
    try {
      return jsonDecode(entry.jsonData) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Delete catalog for a given mode+lang (used on language change).
  Future<void> deleteCatalog(String mode, String lang) async {
    final key = 'catalog_${mode}_$lang';
    await _isar.writeTxn(() async {
      await _isar.catalogEntrys.deleteByKey(key);
    });
  }

  /// Delete all stored catalogs (used when language changes).
  Future<void> deleteAllCatalogs() async {
    await _isar.writeTxn(() async {
      await _isar.catalogEntrys.clear();
    });
  }

  // ─── State Operations ───

  /// Store local state JSON.
  Future<void> storeLocalState(Map<String, dynamic> stateJson) async {
    final entry = StateEntry()
      ..key = 'local_state'
      ..jsonData = jsonEncode(stateJson);
    await _isar.writeTxn(() async {
      await _isar.stateEntrys.putByKey(entry);
    });
  }

  /// Load local state JSON. Returns null if not stored.
  Future<Map<String, dynamic>?> loadLocalState() async {
    final entry =
        await _isar.stateEntrys.where().keyEqualTo('local_state').findFirst();
    if (entry == null) return null;
    try {
      return jsonDecode(entry.jsonData) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Close database (for testing / cleanup).
  Future<void> close() async {
    await _isar.close();
    _initialized = false;
    _instance = null;
  }
}
