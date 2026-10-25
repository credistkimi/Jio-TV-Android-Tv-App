import 'storage_service.dart';

/// Abstract contract for the local stream proxy
abstract class StreamProxy {
  Future<void> start();
  Future<void> stop();
  bool get isRunning;
  String? get baseUrl;

  String buildPlayableUrl({
    required String rawMasterUrl,
    required String channelId,
  });
}

/// Factory function overridden by platform-specific implementations
StreamProxy createStreamProxy(StorageService storageService) =>
    throw UnsupportedError('Cannot create StreamProxy on this platform');
