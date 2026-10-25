import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jio_tv_plus_flutter/models/channel.dart';
import 'package:jio_tv_plus_flutter/services/fire_tv_epg_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.jio.tvplus/fire_tv_epg');
  late FireTvEpgService epgService;
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'getInitialChannelId':
          return '104';
        case 'syncChannels':
          return 1052;
        case 'syncDefaultPrograms':
          return true;
        case 'triggerSystemSync':
          return true;
        case 'getSyncStatus':
          return {
            'channelCount': 1052,
            'lastSyncTime': 1700000000000,
            'inputId': 'com.jio.tvplus/.tif.JioTvInputService',
          };
        default:
          return null;
      }
    });

    epgService = FireTvEpgService();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getInitialChannelId retrieves pending channel ID', () async {
    final result = await epgService.getInitialChannelId();
    expect(result, '104');
    expect(log, hasLength(1));
    expect(log.first.method, 'getInitialChannelId');
  });

  test('syncChannelsToFireTv formats channel list and invokes syncChannels', () async {
    final testChannels = [
      Channel(
        channelId: '104',
        channelNo: 104,
        channelName: 'Aaj Tak',
        logoUrl: 'https://test.com/aajtak.png',
        streamUrl: 'https://test.com/aajtak.m3u8',
        category: 'News',
        language: 'Hindi',
      ),
    ];

    final count = await epgService.syncChannelsToFireTv(testChannels);
    expect(count, 1052);
    expect(log, hasLength(1));
    expect(log.first.method, 'syncChannels');
    expect(log.first.arguments, isA<Map>());
    expect(log.first.arguments['channelsJson'], contains('Aaj Tak'));
  });

  test('syncDefaultPrograms invokes method channel', () async {
    final result = await epgService.syncDefaultPrograms();
    expect(result, isTrue);
    expect(log.first.method, 'syncDefaultPrograms');
  });

  test('triggerSystemSync invokes method channel', () async {
    final result = await epgService.triggerSystemSync();
    expect(result, isTrue);
    expect(log.first.method, 'triggerSystemSync');
  });

  test('getSyncStatus returns valid status map', () async {
    final status = await epgService.getSyncStatus();
    expect(status['channelCount'], 1052);
    expect(status['inputId'], contains('JioTvInputService'));
  });

  test('onChannelSelectedFromFireTv callback is invoked when platform sends event', () async {
    String? tunedChannel;
    epgService.setOnChannelSelectedListener((chId) {
      tunedChannel = chId;
    });

    // Simulate native platform sending event down to Flutter
    final ByteData message = const StandardMethodCodec()
        .encodeMethodCall(const MethodCall('onChannelSelectedFromFireTv', '201'));

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('com.jio.tvplus/fire_tv_epg', message, (ByteData? reply) {});

    expect(tunedChannel, '201');
  });
}
