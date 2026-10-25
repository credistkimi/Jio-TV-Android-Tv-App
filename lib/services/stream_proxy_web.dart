import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';
import 'stream_proxy_stub.dart';

StreamProxy createStreamProxy(StorageService storageService) =>
    StreamProxyWeb(storageService);

/// Web fallback proxy handler.
///
/// In Web browsers (Chrome/Firefox/Safari), the browser's JavaScript sandbox
/// prevents binding local TCP listening sockets (`dart:io` HttpServer).
///
/// If an external local proxy (such as `companion_proxy.py` or `jiotv_go` on `http://localhost:5001`)
/// is running, requests are seamlessly routed through it to avoid CORS and AES-128 key WAF blocks.
class StreamProxyWeb implements StreamProxy {
  final StorageService storageService;
  String? _externalProxyUrl;

  StreamProxyWeb(this.storageService);

  @override
  bool get isRunning => _externalProxyUrl != null;

  @override
  String? get baseUrl => _externalProxyUrl;

  @override
  Future<void> start() async {
    debugPrint('🌐 [StreamProxyWeb] Web platform detected. Checking for companion proxy on http://127.0.0.1:5001...');
    try {
      final res = await http
          .get(Uri.parse('http://127.0.0.1:5001/health'))
          .timeout(const Duration(milliseconds: 700));
      if (res.statusCode == 200) {
        _externalProxyUrl = 'http://127.0.0.1:5001';
        debugPrint('✅ [StreamProxyWeb] Connected to local companion proxy on $_externalProxyUrl');
      }
    } catch (_) {
      debugPrint('ℹ️ [StreamProxyWeb] No companion proxy detected on :5001. Using direct CDN stream.');
    }
  }

  @override
  Future<void> stop() async {
    _externalProxyUrl = null;
  }

  void configureExternalProxy(String? proxyBaseUrl) {
    _externalProxyUrl = proxyBaseUrl;
  }

  @override
  String buildPlayableUrl({
    required String rawMasterUrl,
    required String channelId,
  }) {
    if (_externalProxyUrl != null && _externalProxyUrl!.isNotEmpty) {
      final uri = Uri.tryParse(rawMasterUrl);
      final hdnea = uri?.queryParameters['__hdnea__'] ?? uri?.queryParameters['hdnea'] ?? '';
      final base = _externalProxyUrl!.replaceAll(RegExp(r'/+$'), '');
      return '$base/variant.m3u8?channel_id=$channelId&hdnea=${Uri.encodeComponent(hdnea)}&url=${Uri.encodeComponent(rawMasterUrl)}';
    }
    return rawMasterUrl;
  }
}
