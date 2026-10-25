import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants/tv_api_constants.dart';
import 'storage_service.dart';
import 'stream_proxy_stub.dart';

StreamProxy createStreamProxy(StorageService storageService) =>
    StreamProxyIO(storageService);

/// High-performance embedded HTTP proxy running on `127.0.0.1` via `dart:io`.
///
/// Resolves and bypasses the 3 primary constraints of JioTV HLS streaming:
/// 1. Rewrites AES-128 `#EXT-X-KEY` URLs to local `/key` endpoint, injecting
///    required DRM headers (`ssotoken`, `uniqueId`, `channelId`, `srno`)
///    WITHOUT sending browser `Origin` headers (which Jio's WAF blocks with 403).
/// 2. Rewrites child `.m3u8` variant playlists and appends `?__hdnea__=` tokens
///    or proxies `.ts` chunks to eliminate 403 Forbidden on Akamai CDN.
/// 3. Injects standard CORS headers (`Access-Control-Allow-Origin: *`) to allow
///    uninhibited player playback.
class StreamProxyIO implements StreamProxy {
  final StorageService _storageService;
  HttpServer? _server;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  // In-memory cache for recent tokens
  final Map<String, String> _hdneaCache = {};

  StreamProxyIO(this._storageService);

  @override
  bool get isRunning => _server != null;

  @override
  String? get baseUrl => _server != null ? 'http://127.0.0.1:${_server!.port}' : null;

  @override
  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      debugPrint('==================== [StreamProxyIO] Proxy Started ====================');
      debugPrint('Local Proxy listening on: $baseUrl');
      _server!.listen(_handleRequest, onError: (e) {
        debugPrint('❌ [StreamProxyIO] Server error: $e');
      });
    } catch (e) {
      debugPrint('❌ [StreamProxyIO] Failed to bind local server: $e');
    }
  }

  @override
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _hdneaCache.clear();
    debugPrint('🛑 [StreamProxyIO] Local Proxy Stopped');
  }

  @override
  String buildPlayableUrl({
    required String rawMasterUrl,
    required String channelId,
  }) {
    if (!isRunning || rawMasterUrl.isEmpty) {
      return rawMasterUrl;
    }
    // Extract and cache any incoming hdnea token
    final uri = Uri.tryParse(rawMasterUrl);
    final token = uri?.queryParameters['__hdnea__'] ?? uri?.queryParameters['hdnea'];
    if (token != null && token.isNotEmpty) {
      _hdneaCache[channelId] = token;
    }

    final encodedUrl = Uri.encodeComponent(rawMasterUrl);
    return '$baseUrl/live.m3u8?channelId=$channelId&url=$encodedUrl';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    // Add CORS headers for players
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    final path = request.uri.path;
    try {
      if (path == '/live.m3u8') {
        await _handleMasterPlaylist(request);
      } else if (path == '/variant.m3u8') {
        await _handleVariantPlaylist(request);
      } else if (path == '/key') {
        await _handleKeyRequest(request);
      } else if (path == '/ts') {
        await _handleSegmentRequest(request);
      } else {
        response.statusCode = HttpStatus.notFound;
        response.write('Not found');
        await response.close();
      }
    } catch (e, stack) {
      debugPrint('❌ [StreamProxyIO] Error handling $path: $e\n$stack');
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.write('Proxy error: $e');
        await response.close();
      } catch (_) {}
    }
  }

  /// 1. Handle Master Playlist
  Future<void> _handleMasterPlaylist(HttpRequest request) async {
    final channelId = request.uri.queryParameters['channelId'] ?? '';
    final targetUrl = request.uri.queryParameters['url'] ?? '';

    if (targetUrl.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final targetUri = Uri.parse(targetUrl);
    final hdnea = targetUri.queryParameters['__hdnea__'] ??
        targetUri.queryParameters['hdnea'] ??
        _hdneaCache[channelId] ??
        '';

    if (hdnea.isNotEmpty) {
      _hdneaCache[channelId] = hdnea;
    }

    final clientReq = await _client.getUrl(targetUri);
    clientReq.headers.set('User-Agent', TvApiConstants.userAgentExoPlayer);
    clientReq.headers.set('Accept', '*/*');
    if (hdnea.isNotEmpty) {
      clientReq.headers.set('Cookie', '__hdnea__=$hdnea');
    }

    final clientResp = await clientReq.close();
    if (clientResp.statusCode != HttpStatus.ok) {
      request.response.statusCode = clientResp.statusCode;
      await clientResp.pipe(request.response);
      return;
    }

    final body = await utf8.decoder.bind(clientResp).join();
    final lines = body.split('\n');
    final rewritten = <String>[];

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        rewritten.add(line);
        continue;
      }
      if (trimmed.startsWith('#')) {
        rewritten.add(line);
        continue;
      }

      // This is a variant playlist URL line
      final resolvedUri = targetUri.resolve(trimmed);
      final encodedResolved = Uri.encodeComponent(resolvedUri.toString());
      final proxyVariantUrl =
          '$baseUrl/variant.m3u8?channelId=$channelId&hdnea=${Uri.encodeComponent(hdnea)}&url=$encodedResolved';
      rewritten.add(proxyVariantUrl);
    }

    final output = rewritten.join('\n');
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.write(output);
    await request.response.close();
  }

  /// 2. Handle Variant (Child) Playlist
  Future<void> _handleVariantPlaylist(HttpRequest request) async {
    final channelId = request.uri.queryParameters['channelId'] ?? '';
    final targetUrl = request.uri.queryParameters['url'] ?? '';
    final hdnea = request.uri.queryParameters['hdnea'] ?? _hdneaCache[channelId] ?? '';

    if (targetUrl.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final targetUri = Uri.parse(targetUrl);
    final clientReq = await _client.getUrl(targetUri);
    clientReq.headers.set('User-Agent', TvApiConstants.userAgentExoPlayer);
    clientReq.headers.set('Accept', '*/*');
    if (hdnea.isNotEmpty) {
      clientReq.headers.set('Cookie', '__hdnea__=$hdnea');
    }

    final clientResp = await clientReq.close();
    if (clientResp.statusCode != HttpStatus.ok) {
      request.response.statusCode = clientResp.statusCode;
      await clientResp.pipe(request.response);
      return;
    }

    final body = await utf8.decoder.bind(clientResp).join();
    final lines = body.split('\n');
    final rewritten = <String>[];

    // Regex to detect AES-128 key directive: #EXT-X-KEY:METHOD=AES-128,URI="..."
    final keyRegex = RegExp(r'#EXT-X-KEY:METHOD=([^,]+),URI="([^"]+)"(.*)');

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        rewritten.add(line);
        continue;
      }

      final keyMatch = keyRegex.firstMatch(trimmed);
      if (keyMatch != null) {
        final method = keyMatch.group(1);
        final rawKeyUrl = keyMatch.group(2)!;
        final rest = keyMatch.group(3) ?? '';
        final resolvedKeyUri = targetUri.resolve(rawKeyUrl);
        final encodedKeyUrl = Uri.encodeComponent(resolvedKeyUri.toString());
        final proxyKeyUrl =
            '$baseUrl/key?channelId=$channelId&hdnea=${Uri.encodeComponent(hdnea)}&url=$encodedKeyUrl';
        rewritten.add('#EXT-X-KEY:METHOD=$method,URI="$proxyKeyUrl"$rest');
        continue;
      }

      if (trimmed.startsWith('#')) {
        rewritten.add(line);
        continue;
      }

      // Media segment line (.ts or .aac)
      final resolvedSegUri = targetUri.resolve(trimmed);
      final encodedSegUrl = Uri.encodeComponent(resolvedSegUri.toString());
      final proxySegUrl =
          '$baseUrl/ts?channelId=$channelId&hdnea=${Uri.encodeComponent(hdnea)}&url=$encodedSegUrl';
      rewritten.add(proxySegUrl);
    }

    final output = rewritten.join('\n');
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.write(output);
    await request.response.close();
  }

  /// 3. Handle AES-128 Key Request
  /// Fetches the decryption key from `tv.media.jio.com` using native socket headers
  /// without browser `Origin` headers that trigger 403 Forbidden.
  Future<void> _handleKeyRequest(HttpRequest request) async {
    final channelId = request.uri.queryParameters['channelId'] ?? '';
    final targetUrl = request.uri.queryParameters['url'] ?? '';
    final hdnea = request.uri.queryParameters['hdnea'] ?? _hdneaCache[channelId] ?? '';

    if (targetUrl.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final ssoToken = _storageService.getSsoToken();
    final uniqueId = _storageService.getUniqueId();
    final crmId = _storageService.getCrmId();

    debugPrint('🔑 [StreamProxyIO] Proxying AES-128 key request for Channel $channelId');
    debugPrint('🔑 [StreamProxyIO] Upstream Key URL: $targetUrl');

    final targetUri = Uri.parse(targetUrl);
    final clientReq = await _client.getUrl(targetUri);

    // Required headers for tv.media.jio.com key server
    clientReq.headers.set('User-Agent', TvApiConstants.userAgentExoPlayer);
    clientReq.headers.set('appkey', TvApiConstants.appKey);
    clientReq.headers.set('channelId', channelId);
    clientReq.headers.set('channel_id', channelId);
    if (crmId != null && crmId.isNotEmpty) {
      clientReq.headers.set('crmid', crmId);
      clientReq.headers.set('userId', crmId);
      clientReq.headers.set('subscriberId', crmId);
    }
    if (uniqueId != null && uniqueId.isNotEmpty) {
      clientReq.headers.set('uniqueId', uniqueId);
    }
    clientReq.headers.set('deviceId', TvApiConstants.staticAndroidId);
    clientReq.headers.set('deviceid', TvApiConstants.staticAndroidId);
    clientReq.headers.set('devicetype', TvApiConstants.deviceType);
    clientReq.headers.set('os', TvApiConstants.os);
    clientReq.headers.set('usergroup', TvApiConstants.userGroup);
    clientReq.headers.set('versionCode', TvApiConstants.versionCode);
    clientReq.headers.set('srno', '230203144000');
    if (ssoToken != null && ssoToken.isNotEmpty) {
      clientReq.headers.set('ssotoken', ssoToken);
      clientReq.headers.set('ssoToken', ssoToken);
    }
    if (hdnea.isNotEmpty) {
      clientReq.headers.set('Cookie', '__hdnea__=$hdnea');
    }

    // Explicitly ensure NO Origin or Referer header is sent to tv.media.jio.com
    clientReq.headers.removeAll('Origin');
    clientReq.headers.removeAll('Referer');

    final clientResp = await clientReq.close();
    debugPrint('🔑 [StreamProxyIO] Key response status code: ${clientResp.statusCode}');

    if (clientResp.statusCode != HttpStatus.ok) {
      request.response.statusCode = clientResp.statusCode;
      await clientResp.pipe(request.response);
      return;
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set('Content-Type', 'application/octet-stream');
    request.response.headers.set('Cache-Control', 'no-cache');
    await clientResp.pipe(request.response);
  }

  /// 4. Handle Media Segment (.ts / .aac) Request
  Future<void> _handleSegmentRequest(HttpRequest request) async {
    final channelId = request.uri.queryParameters['channelId'] ?? '';
    final targetUrl = request.uri.queryParameters['url'] ?? '';
    final hdnea = request.uri.queryParameters['hdnea'] ?? _hdneaCache[channelId] ?? '';

    if (targetUrl.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final targetUri = Uri.parse(targetUrl);
    final clientReq = await _client.getUrl(targetUri);
    clientReq.headers.set('User-Agent', TvApiConstants.userAgentExoPlayer);
    clientReq.headers.set('Accept', '*/*');
    if (hdnea.isNotEmpty) {
      clientReq.headers.set('Cookie', '__hdnea__=$hdnea');
    }

    // Forward range header if present for seekable chunks
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      clientReq.headers.set(HttpHeaders.rangeHeader, rangeHeader);
    }

    final clientResp = await clientReq.close();
    request.response.statusCode = clientResp.statusCode;

    // Forward content headers
    clientResp.headers.forEach((name, values) {
      if (name.toLowerCase() != 'set-cookie') {
        for (final val in values) {
          request.response.headers.add(name, val);
        }
      }
    });

    await clientResp.pipe(request.response);
  }
}
