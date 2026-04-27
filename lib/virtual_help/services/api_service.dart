import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Handles all HTTP communication with the catalog server.
class ApiService {
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch the lightweight catalog version string for a mode.
  /// Returns the version string, or null on failure.
  Future<String?> fetchCatalogVersion(String mode) async {
    try {
      final uri = Uri.parse(
          '${VirtualHelpConfig.serverBaseUrl}/api/catalog_version?mode=$mode');
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return body['catalog_version'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch the full catalog for a mode + language.
  /// Returns parsed JSON map, or null on failure.
  Future<Map<String, dynamic>?> fetchCatalog(String mode, String lang) async {
    try {
      final uri = Uri.parse(
          '${VirtualHelpConfig.serverBaseUrl}/api/catalog?mode=$mode&lang=$lang');
      final response = await _client.get(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
