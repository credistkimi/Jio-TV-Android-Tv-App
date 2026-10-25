import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/channel.dart';

/// Service interfacing between Flutter UI and native Android TV Input Framework (TIF).
/// Reference: Amazon Fire TV Linear TV Integration Guide
/// - https://developer.amazon.com/docs/fire-tv/introduction-linear-tv-integration.html
/// - https://developer.amazon.com/docs/fire-tv/tv-input-framework-on-fire-tv.html
/// - https://developer.amazon.com/docs/fire-tv/insert-your-first-channel.html
/// - https://developer.amazon.com/docs/fire-tv/playback-in-fire-tv-ui.html
class FireTvEpgService {
  static const MethodChannel _channel = MethodChannel('com.jio.tvplus/fire_tv_epg');

  Function(String channelId)? _onChannelSelected;

  FireTvEpgService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  void setOnChannelSelectedListener(Function(String channelId) listener) {
    _onChannelSelected = listener;
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onChannelSelectedFromFireTv') {
      final channelId = call.arguments?.toString();
      if (channelId != null && channelId.isNotEmpty) {
        _onChannelSelected?.call(channelId);
      }
    }
  }

  /// Retrieves any channel ID requested upon app launch from Fire TV Channel Guide or "On Now" tile.
  Future<String?> getInitialChannelId() async {
    try {
      final result = await _channel.invokeMethod<String>('getInitialChannelId');
      return result;
    } catch (e) {
      debugPrint('FireTvEpgService: getInitialChannelId error: $e');
      return null;
    }
  }

  /// Synchronizes full live channel catalog into Android's TvContract database for Fire TV Guide.
  Future<int> syncChannelsToFireTv(List<Channel> channels) async {
    try {
      final jsonList = channels.map((c) => {
        'channel_id': c.channelId,
        'channel_order': c.channelNo,
        'channel_name': c.channelName,
        'category': c.category,
        'language': c.language,
        'logoUrl': c.logoUrl,
        'logoFilename': c.logoFilename,
        'streamUrl': c.streamUrl,
      }).toList();

      final jsonString = json.encode(jsonList);
      final count = await _channel.invokeMethod<int>('syncChannels', {
        'channelsJson': jsonString,
      });
      return count ?? 0;
    } catch (e) {
      debugPrint('FireTvEpgService: syncChannelsToFireTv error: $e');
      return 0;
    }
  }

  /// Injects rolling program schedule (EPG) blocks for all channels into TvContract.
  Future<bool> syncDefaultPrograms() async {
    try {
      final result = await _channel.invokeMethod<bool>('syncDefaultPrograms');
      return result ?? false;
    } catch (e) {
      debugPrint('FireTvEpgService: syncDefaultPrograms error: $e');
      return false;
    }
  }

  /// Schedules or immediately triggers background EpgSyncWorker.
  Future<bool> triggerSystemSync() async {
    try {
      final result = await _channel.invokeMethod<bool>('triggerSystemSync');
      return result ?? false;
    } catch (e) {
      debugPrint('FireTvEpgService: triggerSystemSync error: $e');
      return false;
    }
  }

  /// Retrieves current synchronization status from Android TvContract and SharedPreferences.
  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getSyncStatus');
      return result ?? {};
    } catch (e) {
      debugPrint('FireTvEpgService: getSyncStatus error: $e');
      return {};
    }
  }
}
