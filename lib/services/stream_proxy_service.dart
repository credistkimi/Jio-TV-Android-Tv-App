import 'storage_service.dart';
import 'stream_proxy_stub.dart';
import 'stream_proxy_stub.dart'
    if (dart.library.io) 'stream_proxy_io.dart'
    if (dart.library.js_interop) 'stream_proxy_web.dart'
    as proxy_factory;

export 'stream_proxy_stub.dart';

/// Central stream proxy manager that coordinates local playback routing
/// across Native (Android, Windows, macOS, Linux) and Web platforms.
class StreamProxyService {
  final StorageService _storageService;
  late final StreamProxy _proxy;

  StreamProxyService(this._storageService) {
    _proxy = proxy_factory.createStreamProxy(_storageService);
  }

  Future<void> start() => _proxy.start();
  Future<void> stop() => _proxy.stop();
  bool get isRunning => _proxy.isRunning;
  String? get baseUrl => _proxy.baseUrl;

  /// Returns the stream URL that the player should consume.
  ///
  /// On platforms running the embedded proxy, the stream is routed through
  /// `http://127.0.0.1:<port>/live.m3u8` to handle AES key decryption and
  /// Akamai edge tokens seamlessly.
  String buildPlayableUrl({
    required String rawMasterUrl,
    required String channelId,
  }) {
    return _proxy.buildPlayableUrl(
      rawMasterUrl: rawMasterUrl,
      channelId: channelId,
    );
  }
}
