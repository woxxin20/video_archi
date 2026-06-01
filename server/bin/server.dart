import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

// ─── Global State ───
late Map<String, dynamic> _videosConfig;
late Map<String, Map<String, String>> _contentMap;
late Map<String, int> _videoDurations;
late Map<String, List<String>> _videoLanguages;
late String _catalogVersion;
/// Default CDN base URL — the public host that serves /videos/<mode>/<cat>/<id>/master.m3u8 etc.
/// Override at runtime via `dart run bin/server.dart <cdn_base_url>` or the CDN_BASE_URL env var.
String _cdnBaseUrl = 'http://192.168.1.57';
final Map<String, Map<String, dynamic>> _catalogCache = {};

void main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;

  // Resolve server root: script is at server/bin/server.dart
  final scriptDir = File(Platform.script.toFilePath()).parent.path;
  final root = Directory(scriptDir).parent.path;

  // CDN base URL resolution priority: CLI arg > env var > default (http://192.168.1.57)
  final envCdn = Platform.environment['CDN_BASE_URL'];
  if (args.isNotEmpty) {
    _cdnBaseUrl = args[0];
  } else if (envCdn != null && envCdn.isNotEmpty) {
    _cdnBaseUrl = envCdn;
  }
  // Strip trailing slash for consistent URL construction
  if (_cdnBaseUrl.endsWith('/')) {
    _cdnBaseUrl = _cdnBaseUrl.substring(0, _cdnBaseUrl.length - 1);
  }

  await _loadConfigs(root);

  final router = Router();
  router.get('/api/catalog', _handleCatalog);
  router.get('/api/catalog_version', _handleCatalogVersion);
  router.get('/health', (Request _) => Response.ok(
        jsonEncode({
          'status': 'ok',
          'catalog_version': _catalogVersion,
          'cdn_base_url': _cdnBaseUrl,
          'langs_loaded': _contentMap.keys.toList()..sort(),
        }),
        headers: {'Content-Type': 'application/json'},
      ));

  // static file handler for videos
  final videoPath = '$root/videos';
  if (!await Directory(videoPath).exists()) {
    await Directory(videoPath).create(recursive: true);
    print('   Created missing videos directory: $videoPath');
  }

  final staticHandler = createStaticHandler(
    videoPath,
    defaultDocument: 'index.html',
  );

  final cascade = Cascade().add(router.call).add((Request request) async {
    final path = request.url.path;
    if (path.startsWith('videos/')) {
      final response = await staticHandler(request.change(path: 'videos/'));

      // Force correct MIME types for HLS files (per architecture §7)
      if (response.statusCode == 200 || response.statusCode == 206) {
        if (path.endsWith('.m3u8')) {
          return response.change(headers: {
            'Content-Type': 'application/vnd.apple.mpegurl',
            'Cache-Control': 'public, max-age=60',
          });
        } else if (path.endsWith('.ts')) {
          return response.change(headers: {
            'Content-Type': 'video/mp2t',
            'Cache-Control': 'public, max-age=31536000',
          });
        } else if (path.endsWith('.aac')) {
          return response.change(headers: {
            'Content-Type': 'audio/aac',
            'Cache-Control': 'public, max-age=31536000',
          });
        } else if (path.endsWith('.webp')) {
          return response.change(headers: {
            'Content-Type': 'image/webp',
            'Cache-Control': 'public, max-age=86400',
          });
        } else if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
          return response.change(headers: {
            'Content-Type': 'image/jpeg',
            'Cache-Control': 'public, max-age=86400',
          });
        }
      }
      return response;
    }
    return Response.notFound('Not Found');
  });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors())
      .addHandler(cascade.handler);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('✅ Server running on http://${server.address.address}:${server.port}');
  print('   CDN: $_cdnBaseUrl | Version: $_catalogVersion');
}

// ─── CORS ───
Middleware _cors() => (Handler h) => (Request r) async {
      if (r.method == 'OPTIONS') {
        return Response.ok('', headers: _ch);
      }
      return (await h(r)).change(headers: _ch);
    };

const _ch = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

// ─── Load Configs ───
Future<void> _loadConfigs(String root) async {
  _videosConfig = jsonDecode(await File('$root/videos.json').readAsString());
  _catalogVersion = _videosConfig['catalog_version'] as String;

  // Durations
  final dRaw =
      jsonDecode(await File('$root/video_durations.json').readAsString())
          as Map<String, dynamic>;
  _videoDurations = {};
  for (final m in dRaw.keys) {
    for (final c in (dRaw[m] as Map<String, dynamic>).keys) {
      for (final id in ((dRaw[m] as Map)[c] as Map<String, dynamic>).keys) {
        _videoDurations['$m/$c/$id'] = ((dRaw[m] as Map)[c] as Map)[id] as int;
      }
    }
  }

  // Video languages
  final lRaw =
      jsonDecode(await File('$root/video_languages.json').readAsString())
          as Map<String, dynamic>;
  _videoLanguages = lRaw.map((k, v) => MapEntry(k, (v as List).cast<String>()));

  // Content translations
  _contentMap = {};
  final langsDir = Directory('$root/content/langs');
  if (await langsDir.exists()) {
    await for (final f in langsDir.list()) {
      if (f is File && f.path.endsWith('.json')) {
        final m =
            RegExp(r'content\.(\w+)\.json').firstMatch(f.uri.pathSegments.last);
        if (m != null) {
          final lang = m.group(1)!;
          final data =
              jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          _contentMap[lang] = data.cast<String, String>();
          print('   Loaded lang: $lang (${data.length} keys)');
        }
      }
    }
  }
  print(
      '   ${_videoDurations.length} durations, ${_videoLanguages.length} video-lang mappings');
}

// ─── GET /api/catalog_version ───
Response _handleCatalogVersion(Request request) {
  final mode = request.url.queryParameters['mode'];
  if (mode == null || !['period', 'pregnancy'].contains(mode)) {
    return Response(400,
        body: jsonEncode({'error': 'Invalid mode'}),
        headers: {'Content-Type': 'application/json'});
  }
  return Response.ok(
      jsonEncode({'mode': mode, 'catalog_version': _catalogVersion}),
      headers: {'Content-Type': 'application/json'});
}

// ─── GET /api/catalog ───
Response _handleCatalog(Request request) {
  final mode = request.url.queryParameters['mode'];
  final lang = request.url.queryParameters['lang'] ?? 'en';
  if (mode == null || !['period', 'pregnancy'].contains(mode)) {
    return Response(400,
        body: jsonEncode({'error': 'Invalid mode'}),
        headers: {'Content-Type': 'application/json'});
  }

  final ck = '$mode:$lang:$_catalogVersion';
  if (_catalogCache.containsKey(ck)) {
    return Response.ok(jsonEncode(_catalogCache[ck]),
        headers: {'Content-Type': 'application/json'});
  }

  final catalog = _buildCatalog(mode, lang);
  _catalogCache[ck] = catalog;
  return Response.ok(jsonEncode(catalog),
      headers: {'Content-Type': 'application/json'});
}

// ─── Build Catalog ───
Map<String, dynamic> _buildCatalog(String mode, String reqLang) {
  final modeData = _videosConfig[mode] as Map<String, dynamic>;
  final langResolved = _contentMap.containsKey(reqLang) ? reqLang : 'en';
  final categories = <String, dynamic>{};

  for (final cat in modeData.keys) {
    final ids = (modeData[cat] as List).cast<String>();
    final videos = <Map<String, dynamic>>[];
    for (final id in ids) {
      final fid = '$mode/$cat/$id';
      final tKey = '${mode}_${cat}_${id}_title';
      final dKey = '${mode}_${cat}_${id}_desc';
      final preferredAudioLang = _resolveAudioLang(fid, reqLang);
      final availableAudioLangs = _getAvailableAudioLangs(fid);

      videos.add({
        'id': id,
        'full_id': fid,
        'title': _resolveText(tKey, langResolved),
        'description': _resolveText(dKey, langResolved),
        'duration_sec': _videoDurations[fid] ?? 60,
        'stream_url': '$_cdnBaseUrl/videos/$fid/master.m3u8',
        'thumbnail_url': '$_cdnBaseUrl/videos/$fid/Thumbnail.webp',
        'preferred_audio_lang': preferredAudioLang,
        'available_audio_langs': availableAudioLangs,
        'video_lang_resolved': preferredAudioLang,
        'active': true,
      });
    }
    categories[cat] = {'total': ids.length, 'videos': videos};
  }

  return {
    'mode': mode,
    'lang': reqLang,
    'lang_resolved': langResolved,
    'catalog_version': _catalogVersion,
    'categories': categories,
  };
}

String _resolveText(String key, String lang) {
  if (_contentMap[lang]?.containsKey(key) == true) {
    return _contentMap[lang]![key]!;
  }
  if (_contentMap['en']?.containsKey(key) == true) {
    return _contentMap['en']![key]!;
  }
  return key;
}

String _resolveAudioLang(String fullId, String reqLang) {
  final avail = _videoLanguages[fullId] ?? ['en'];
  if (avail.contains(reqLang)) return reqLang;
  if (avail.contains('hi')) return 'hi';
  return 'en';
}

List<String> _getAvailableAudioLangs(String fullId) {
  return _videoLanguages[fullId] ?? ['en'];
}
