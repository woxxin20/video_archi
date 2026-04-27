import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Manages the per-device install ID (UUID v4).
/// Generated once on first launch, persisted in SharedPreferences.
/// Never sent to server — used only for local deterministic shuffling.
class InstallIdService {
  static const _key = 'virtual_help_install_id';

  /// Returns existing install ID or creates and stores a new one.
  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_key);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_key, id);
    }
    return id;
  }
}
