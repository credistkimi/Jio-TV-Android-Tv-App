import 'package:flutter_test/flutter_test.dart';
import 'package:jio_tv_plus_flutter/services/storage_service.dart';
import 'package:jio_tv_plus_flutter/services/stream_proxy_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('StreamProxyService lifecycle and URL rewriting', () async {
    SharedPreferences.setMockInitialValues({
      'sso_token': 'test_sso_token',
      'access_token': 'test_access_token',
      'crm_id': '12345678',
      'unique_id': 'test-unique-id',
    });
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final proxyService = StreamProxyService(storage);

    expect(proxyService.isRunning, false);

    // Before starting, buildPlayableUrl returns raw URL
    const rawUrl = 'https://jiotvbpkmob.cdn.jio.com/bpk-tv/Colors_HD_MOB/Live/index.m3u8?__hdnea__=st=123~exp=456~acl=/*~hmac=abc';
    final unproxiedUrl = proxyService.buildPlayableUrl(
      rawMasterUrl: rawUrl,
      channelId: '144',
    );
    expect(unproxiedUrl, rawUrl);

    // Start proxy
    await proxyService.start();
    expect(proxyService.isRunning, true);
    expect(proxyService.baseUrl, isNotNull);
    expect(proxyService.baseUrl!.startsWith('http://127.0.0.1:'), true);

    // When running, rewrites master URL to localhost
    final proxiedUrl = proxyService.buildPlayableUrl(
      rawMasterUrl: rawUrl,
      channelId: '144',
    );
    expect(proxiedUrl.startsWith('${proxyService.baseUrl}/live.m3u8?channelId=144&url='), true);

    // Stop proxy
    await proxyService.stop();
    expect(proxyService.isRunning, false);
  });
}
