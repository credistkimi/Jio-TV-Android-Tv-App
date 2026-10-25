import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jio_tv_plus_flutter/constants/tv_api_constants.dart';
import 'package:jio_tv_plus_flutter/models/channel.dart';
import 'package:jio_tv_plus_flutter/widgets/tv_channel_logo.dart';

void main() {
  group('Channel Logo URL Resolution (jiotv_go & JioTV CDN spec)', () {
    test('Channel parses raw filename into primary dare_images CDN and backup img.media.jio.com mirror', () {
      final ch = Channel.fromJson({
        'channel_id': 143,
        'channel_name': 'CNBC TV18',
        'channel_order': 143,
        'channel_category_name': 'News',
        'channel_logo': 'CNBCTV181.png',
      });

      expect(ch.logoFilename, 'CNBCTV181.png');
      expect(ch.logoUrl, 'https://jiotv.catchup.cdn.jio.com/dare_images/images/CNBCTV181.png');
      expect(ch.backupLogoUrl, 'https://img.media.jio.com/apis/v1.4/getchannelimage/get/CNBCTV181.png');
    });

    test('Channel handles full URL in logoUrl by extracting basename for backup mirror', () {
      final ch = Channel(
        channelId: '101',
        channelName: 'NDTV Profit',
        channelNo: 101,
        category: 'Business',
        language: 'English',
        streamUrl: 'https://jiotvcod.cdn.jio.com/bpk-tv/NDTV_Profit_MOB/Live/index.m3u8',
        logoUrl: 'https://jiotv.catchup.cdn.jio.com/dare_images/images/NDTV_Profit.png',
      );

      expect(ch.logoFilename, 'NDTV_Profit.png');
      expect(ch.logoUrl, 'https://jiotv.catchup.cdn.jio.com/dare_images/images/NDTV_Profit.png');
      expect(ch.backupLogoUrl, 'https://img.media.jio.com/apis/v1.4/getchannelimage/get/NDTV_Profit.png');
    });

    testWidgets('TvChannelLogo renders channel fallback text badge when logo is empty', (tester) async {
      final channelWithoutLogo = Channel(
        channelId: '999',
        channelName: 'Test Channel HD',
        channelNo: 999,
        category: 'General',
        language: 'Hindi',
        streamUrl: 'https://jiotvcod.cdn.jio.com/bpk-tv/Test_MOB/Live/index.m3u8',
        logoUrl: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvChannelLogo(
              channel: channelWithoutLogo,
              height: 48,
            ),
          ),
        ),
      );

      expect(find.text('Test Channel HD'), findsOneWidget);
    });
  });

  group('Playback Headers & ExoPlayer integration', () {
    test('TvApiConstants.buildPlaybackHeaders matches exact jiotv_go & capture curl parameters', () {
      final headers = TvApiConstants.buildPlaybackHeaders(
        channelId: '143',
        token: 'dummy_sso_token_123',
      );

      expect(headers['appkey'], 'l7xx938b6684ee9e4bbe8831a9a682b8e19f');
      expect(headers['appname'], 'RJIL_JioTV');
      expect(headers['channel_id'], '143');
      expect(headers['devicetype'], 'phone');
      expect(headers['os'], 'android');
      expect(headers['versioncode'], '422');
      expect(headers['usergroup'], 'tvYR7NSNn7rymo3F');
      expect(headers['usertype'], 'JIO');
      expect(headers['isott'], 'false');
      expect(headers['lbcookie'], '1');
      expect(headers['languageid'], '6');
      expect(headers['User-Agent'], 'okhttp/4.12.0');
      expect(headers['accesstoken'], 'dummy_sso_token_123');
      expect(headers['ssotoken'], 'dummy_sso_token_123');
      expect(headers['Authorization'], 'Bearer dummy_sso_token_123');
    });

    test('TvApiConstants.buildPlaybackHeaders distinguishes ES256 authToken vs HS256 ssoToken', () {
      const es256AuthToken = 'eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.dummy_es256_payload.signature';
      const hs256SsoToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummy_hs256_payload.signature';

      final headers = TvApiConstants.buildPlaybackHeaders(
        channelId: '143',
        accessToken: es256AuthToken,
        ssoToken: hs256SsoToken,
        crmId: '1294939140',
        uniqueId: '2dfe9e7f-9c24-4db7-96a8-55f0488cfdd1',
      );

      // accesstoken MUST receive the ES256 token (authToken) to prevent 419 "unexpected method: HS256"
      expect(headers['accesstoken'], es256AuthToken);
      expect(headers['Authorization'], 'Bearer $es256AuthToken');

      // ssotoken receives the HS256 token
      expect(headers['ssotoken'], hs256SsoToken);

      // Subscriber CRM attributes
      expect(headers['crmid'], '1294939140');
      expect(headers['userId'], '1294939140');
      expect(headers['subscriberId'], '1294939140');
      expect(headers['uniqueId'], '2dfe9e7f-9c24-4db7-96a8-55f0488cfdd1');
    });
  });
}
