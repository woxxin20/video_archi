import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Result of an API call: either a parsed body or a structured error.
/// Lets the provider surface the *actual* failure to the user instead of
/// silently dropping to "you appear to be offline".
class ApiResult<T> {
  final T? data;
  final String? error;

  const ApiResult.ok(T this.data) : error = null;
  const ApiResult.fail(String this.error) : data = null;

  bool get isOk => error == null;
}

/// Handles all HTTP communication with the catalog server.
class ApiService {
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch the lightweight catalog version string for a mode.
  Future<ApiResult<String>> fetchCatalogVersion(String mode) async {
    final url =
        '${VirtualHelpConfig.serverBaseUrl}/api/catalog_version?mode=$mode';
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      debugPrint('[ApiService] GET $url → ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final version = body['catalog_version'] as String?;
        if (version == null) {
          return const ApiResult.fail(
              'Server response missing "catalog_version"');
        }
        return ApiResult.ok(version);
      }
      return ApiResult.fail(
          'Server returned HTTP ${response.statusCode} for catalog_version');
    } on TimeoutException {
      debugPrint('[ApiService] TIMEOUT $url');
      return const ApiResult.fail(
          'Server timed out. Is the catalog server reachable?');
    } catch (e) {
      debugPrint('[ApiService] ERROR $url: $e');
      return ApiResult.fail('Network error: $e');
    }
  }

  /// Fetch the full catalog for a mode + language.
  Future<ApiResult<Map<String, dynamic>>> fetchCatalog(
      String mode, String lang) async {
    final url =
        '${VirtualHelpConfig.serverBaseUrl}/api/catalog?mode=$mode&lang=$lang';
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      debugPrint(
          '[ApiService] GET $url → ${response.statusCode} (${response.bodyBytes.length} bytes)');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(body);
      }
      return ApiResult.fail(
          'Server returned HTTP ${response.statusCode} for catalog');
    } on TimeoutException {
      debugPrint('[ApiService] TIMEOUT $url');
      return const ApiResult.fail(
          'Server timed out fetching catalog. Check the server URL.');
    } catch (e) {
      debugPrint('[ApiService] ERROR $url: $e');
      return ApiResult.fail('Network error fetching catalog: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}
