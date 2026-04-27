import 'package:isar_community/isar.dart';

part 'collections.g.dart';

/// Stores full catalog JSON keyed by mode+lang (e.g. "catalog_period_hi").
@collection
class CatalogEntry {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  String key = '';

  String jsonData = '';
}

/// Stores local state JSON (watch queues, cycles, etc.).
@collection
class StateEntry {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  String key = '';

  String jsonData = '';
}
