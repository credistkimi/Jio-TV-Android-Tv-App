/// Official Upstream Jio TV API Constants & Endpoints
/// Based on the reverse-engineered specification in JioTV_API_Documentation.md
class TvApiConstants {
  TvApiConstants._();

  // Upstream Domains from Jio TV API Documentation
  static const String playbackApiDomain = 'jiotvapi.media.jio.com';
  static const String userServiceDomain = 'jiotvapi.media.jio.com';
  static const String authMediaDomain = 'auth.media.jio.com';
  static const String tvMediaDomain = 'tv.media.jio.com';
  static const String cdnDataDomain = 'jiotv.data.cdn.jio.com';
  static const String apiCdnDomain = 'jiotvapi.cdn.jio.com';
  static const String imageCdnDomain = 'img.media.jio.com';
  static const String catchupPosterDomain = 'jiotv.catchup.cdn.jio.com';
  static const String streamCdnDomain = 'jiotvcod.cdn.jio.com';

  // 1. Channel Listing Endpoints (Upstream)
  static const String channelsPrimaryUrl =
      'https://$cdnDataDomain/apis/v3.1/getMobileChannelList/get/?os=android&devicetype=phone&usertype=tvYR7NSNn7rymo3F';
  static const String channelsFallbackUrl =
      'https://$apiCdnDomain/apis/v3.1/getMobileChannelList/get/?langId=6&os=android&devicetype=phone&usertype=JIO&version=315&langId=6';

  // 2. Electronic Program Guide (EPG) Endpoints (Upstream)
  static const String epgPrimaryBaseUrl =
      'https://$cdnDataDomain/apis/v1.3/getepg/get';
  static const String epgFallbackBaseUrl =
      'https://$apiCdnDomain/apis/v1.3/getepg/get';

  // 3. User & Auth Endpoints (Upstream)
  static const String loginOtpSendUrl =
      'https://$userServiceDomain/userservice/apis/v1/loginotp/send';
  static const String loginOtpVerifyUrl =
      'https://$userServiceDomain/userservice/apis/v1/loginotp/verify';
  static const String tokenRefreshUrl =
      'https://$authMediaDomain/tokenservice/apis/v1/refreshtoken?langId=6';
  static const String ssoTokenRefreshUrl =
      'https://$tvMediaDomain/apis/v2.0/loginotp/refresh?langId=6';
  static const String deviceCodeUrl =
      'https://$tvMediaDomain/apis/v2.0/device/code';

  // 4. Playback Resolution Endpoint (Live, Catchup & DRM)
  static const String playbackGetUrl =
      'https://$playbackApiDomain/playback/apis/v1.1/geturl?langId=6';

  // 5. Image & Artwork CDN Endpoints
  static const String channelLogoBaseUrl =
      'https://$catchupPosterDomain/dare_images/images/';
  static const String channelLogoFallbackUrl =
      'https://$imageCdnDomain/apis/v1.4/getchannelimage/get/';
  static const String catchupPosterBaseUrl =
      'https://$catchupPosterDomain/dare_images/shows/';

  // Static Device & OS Parameters (Identical to jiotv_go & Jio TV Android Client)
  static const String deviceType = 'phone';
  static const String os = 'android';
  static const String model = 'SM-G930F'; // Samsung Galaxy S7 static model
  static const String consumptionDeviceName = 'SM-G930F';
  static const String platformName = 'SM-G930F';
  static const String platformType = 'android';
  static const String osVersion = '13';
  static const String staticAndroidId = 'd04b868e404b88df';

  // Static App & Build Parameters
  static const String appName = 'RJIL_JioTV';
  static const String versionCode = '422';
  static const String userAgent = 'okhttp/4.12.0';
  static const String userAgentExoPlayer =
      'plaYtv/7.1.8 (Linux;Android 8.1.0) ExoPlayerLib/2.11.7';
  static const String appKey = 'NzNiMDhlYzQyNjJm';
  static const String apiKeyJio = 'l7xx938b6684ee9e4bbe8831a9a682b8e19f';
  static const String userGroup = 'tvYR7NSNn7rymo3F';
  static const String userType = 'JIO';
  static const String languageId = '6'; // Hindi / National
  static const String isOtt = 'false';
  static const String lbCookie = '1';

  // Category ID Mapping from official Jio TV backend
  static const Map<int, String> categoryMap = {
    5: 'Entertainment',
    6: 'Movies',
    7: 'Kids',
    8: 'Sports',
    9: 'Lifestyle',
    10: 'Infotainment',
    12: 'News',
    13: 'Music',
    15: 'Devotional',
    16: 'Business News',
    17: 'Educational',
    18: 'Shopping',
  };

  // Language ID Mapping from official Jio TV backend
  static const Map<int, String> languageMap = {
    1: 'Hindi',
    2: 'Marathi',
    3: 'Punjabi',
    4: 'Urdu',
    5: 'Bengali',
    6: 'English',
    7: 'Malayalam',
    8: 'Tamil',
    9: 'Gujarati',
    10: 'Odia',
    11: 'Telugu',
    12: 'Bhojpuri',
    13: 'Kannada',
    14: 'Assamese',
    15: 'Nepali',
    16: 'French',
    21: 'Chhattisgarhi',
  };

  /// Build standard headers matching upstream Jio TV API requirements
  static Map<String, String> buildHeaders({
    String? token,
    String? crmId,
    String? uniqueId,
  }) {
    final headers = {
      'User-Agent': userAgent,
      'Accept': 'application/json',
      'devicetype': deviceType,
      'os': os,
      'versionCode': versionCode,
      'appkey': appKey,
      'appname': appName,
      'usertype': userType,
      'usergroup': userGroup,
      'languageId': languageId,
      'isott': isOtt,
      'lbcookie': lbCookie,
      'deviceId': staticAndroidId,
    };

    if (token != null && token.isNotEmpty) {
      headers['ssotoken'] = token;
      headers['accessToken'] = token;
      headers['accesstoken'] = token;
      headers['Authorization'] = 'Bearer $token';
    }
    if (crmId != null && crmId.isNotEmpty) {
      headers['crmid'] = crmId;
      headers['userId'] = crmId;
    }
    if (uniqueId != null && uniqueId.isNotEmpty) {
      headers['uniqueId'] = uniqueId;
    }

    return headers;
  }

  /// Build playback headers matching jiotv_go & JioTV Playback API requirements
  static Map<String, String> buildPlaybackHeaders({
    String? token,
    String? accessToken,
    String? ssoToken,
    String? crmId,
    String? uniqueId,
    required String channelId,
  }) {
    final headers = {
      'accept': 'application/json',
      'accept-language': 'en-US,en;q=0.9',
      'appkey': apiKeyJio,
      'appname': appName,
      'channel_id': channelId,
      'content-type': 'application/x-www-form-urlencoded',
      'deviceid': staticAndroidId,
      'deviceId': staticAndroidId,
      'devicetype': deviceType,
      'isott': isOtt,
      'languageid': languageId,
      'languageId': languageId,
      'lbcookie': lbCookie,
      'os': os,
      'user-agent': userAgent,
      'User-Agent': userAgent,
      'usergroup': userGroup,
      'usertype': userType,
      'versioncode': versionCode,
      'versionCode': versionCode,
    };

    // Separate ES256 (authToken) and HS256 (ssoToken) to prevent 419 "unexpected method: HS256"
    String? es256Token;
    String? hs256Token;

    for (final candidate in [accessToken, token, ssoToken]) {
      if (candidate == null || candidate.isEmpty) continue;
      if (candidate.startsWith('eyJhbGciOiJFUzI1Ni') && es256Token == null) {
        es256Token = candidate;
      } else if (candidate.startsWith('eyJhbGciOiJIUzI1Ni') && hs256Token == null) {
        hs256Token = candidate;
      }
    }

    es256Token ??= accessToken ?? token;
    hs256Token ??= ssoToken ?? token;

    if (crmId != null && crmId.isNotEmpty) {
      headers['crmid'] = crmId;
      headers['userId'] = crmId;
      headers['subscriberId'] = crmId;
    }
    if (uniqueId != null && uniqueId.isNotEmpty) {
      headers['uniqueId'] = uniqueId;
    }

    if (es256Token != null && es256Token.isNotEmpty) {
      headers['accesstoken'] = es256Token;
      headers['accessToken'] = es256Token;
      headers['authorization'] = 'Bearer $es256Token';
      headers['Authorization'] = 'Bearer $es256Token';
    }

    if (hs256Token != null && hs256Token.isNotEmpty) {
      headers['ssotoken'] = hs256Token;
      headers['ssoToken'] = hs256Token;
    }

    return headers;
  }

  /// Construct DeviceInfo payload for OTP verify and login calls
  static Map<String, dynamic> buildDeviceInfoPayload({String? deviceId}) {
    return {
      'consumptionDeviceName': consumptionDeviceName,
      'info': {
        'type': platformType,
        'platform': {
          'name': platformName,
          'version': osVersion,
        },
        'androidId': deviceId ?? staticAndroidId,
      },
    };
  }
}
