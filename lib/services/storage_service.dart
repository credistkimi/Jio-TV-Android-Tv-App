import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keySsoToken = 'jiotv_sso_token';
  static const String _keyAccessToken = 'jiotv_access_token';
  static const String _keyRefreshToken = 'jiotv_refresh_token';
  static const String _keyCrmId = 'jiotv_crm_id';
  static const String _keyUniqueId = 'jiotv_unique_id';
  static const String _keyMobileNumber = 'jiotv_mobile_number';
  static const String _keyFavorites = 'jiotv_favorites';
  static const String _keyLastChannel = 'jiotv_last_channel';
  static const String _keyQuality = 'jiotv_quality';
  static const String _keyLanguage = 'jiotv_language';
  static const String _keyShowPremium = 'jiotv_show_premium';
  static const String _keyPreviewDelay = 'jiotv_preview_delay';
  static const String _keyAutoplayPreview = 'jiotv_autoplay_preview';
  static const String _keyHardwareAccel = 'jiotv_hw_accel';
  static const String _keyLowLatencyMode = 'jiotv_low_latency';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // Auth tokens: ES256 (authToken/accessToken) and HS256 (ssoToken)
  String? getAccessToken() {
    final direct = _prefs.getString(_keyAccessToken);
    if (direct != null && direct.isNotEmpty && direct.startsWith('eyJhbGciOiJFUzI1Ni')) {
      return direct;
    }
    final sso = _prefs.getString(_keySsoToken);
    if (sso != null && sso.isNotEmpty && sso.startsWith('eyJhbGciOiJFUzI1Ni')) {
      return sso;
    }
    return direct ?? sso;
  }
  Future<bool> setAccessToken(String token) => _prefs.setString(_keyAccessToken, token);

  String? getSsoToken() {
    final direct = _prefs.getString(_keySsoToken);
    if (direct != null && direct.isNotEmpty && direct.startsWith('eyJhbGciOiJIUzI1Ni')) {
      return direct;
    }
    final access = _prefs.getString(_keyAccessToken);
    if (access != null && access.isNotEmpty && access.startsWith('eyJhbGciOiJIUzI1Ni')) {
      return access;
    }
    return direct ?? access;
  }
  Future<bool> setSsoToken(String token) => _prefs.setString(_keySsoToken, token);

  String? getCrmId() => _prefs.getString(_keyCrmId);
  Future<bool> setCrmId(String crmId) => _prefs.setString(_keyCrmId, crmId);

  String? getUniqueId() => _prefs.getString(_keyUniqueId);
  Future<bool> setUniqueId(String uniqueId) => _prefs.setString(_keyUniqueId, uniqueId);

  String? getRefreshToken() => _prefs.getString(_keyRefreshToken);
  Future<bool> setRefreshToken(String token) => _prefs.setString(_keyRefreshToken, token);

  String? getMobileNumber() => _prefs.getString(_keyMobileNumber);
  Future<bool> setMobileNumber(String mobile) => _prefs.setString(_keyMobileNumber, mobile);

  bool get isAuthenticated =>
      (getSsoToken()?.isNotEmpty ?? false) || (getAccessToken()?.isNotEmpty ?? false);

  /// Save complete subscriber session matching JioTV & jiotv_go login response
  Future<void> saveAuthSession({
    required String ssoToken,
    String? accessToken,
    String? refreshToken,
    String? crmId,
    String? uniqueId,
    String? mobileNumber,
  }) async {
    String actualSso = ssoToken;
    String? actualAccess = accessToken;

    // Distinguish ES256 authToken vs HS256 ssoToken if passed reversely
    if (ssoToken.startsWith('eyJhbGciOiJFUzI1Ni')) {
      actualAccess = ssoToken;
    }
    if (accessToken != null && accessToken.startsWith('eyJhbGciOiJIUzI1Ni')) {
      actualSso = accessToken;
    }

    await setSsoToken(actualSso);
    if (actualAccess != null && actualAccess.isNotEmpty) {
      await setAccessToken(actualAccess);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await setRefreshToken(refreshToken);
    }
    if (crmId != null && crmId.isNotEmpty) {
      await setCrmId(crmId);
    }
    if (uniqueId != null && uniqueId.isNotEmpty) {
      await setUniqueId(uniqueId);
    }
    if (mobileNumber != null && mobileNumber.isNotEmpty) {
      await setMobileNumber(mobileNumber);
    }
  }

  Future<void> clearAuth() async {
    await _prefs.remove(_keySsoToken);
    await _prefs.remove(_keyAccessToken);
    await _prefs.remove(_keyRefreshToken);
    await _prefs.remove(_keyCrmId);
    await _prefs.remove(_keyUniqueId);
    await _prefs.remove(_keyMobileNumber);
  }

  // Favorites
  List<String> getFavorites() => _prefs.getStringList(_keyFavorites) ?? [];
  Future<bool> toggleFavorite(String channelId) async {
    final list = getFavorites();
    if (list.contains(channelId)) {
      list.remove(channelId);
    } else {
      list.add(channelId);
    }
    return _prefs.setStringList(_keyFavorites, list);
  }

  bool isFavorite(String channelId) => getFavorites().contains(channelId);

  // Last Channel
  String getLastChannelId({String fallback = '104'}) => _prefs.getString(_keyLastChannel) ?? fallback;
  Future<bool> setLastChannelId(String channelId) => _prefs.setString(_keyLastChannel, channelId);

  // Preferred Quality & Language
  String getPreferredQuality() => _prefs.getString(_keyQuality) ?? 'Auto';
  Future<bool> setPreferredQuality(String quality) => _prefs.setString(_keyQuality, quality);

  String getPreferredLanguage() => _prefs.getString(_keyLanguage) ?? 'Hindi';
  Future<bool> setPreferredLanguage(String lang) => _prefs.setString(_keyLanguage, lang);

  // Show Premium Channels preference (Default: false)
  bool getShowPremiumChannels({bool defaultValue = false}) =>
      _prefs.getBool(_keyShowPremium) ?? defaultValue;
  Future<bool> setShowPremiumChannels(bool value) =>
      _prefs.setBool(_keyShowPremium, value);

  // Preview Video Autoplay Settings
  double getPreviewAutoplayDelay({double fallback = 1.0}) =>
      _prefs.getDouble(_keyPreviewDelay) ?? fallback;
  Future<bool> setPreviewAutoplayDelay(double seconds) =>
      _prefs.setDouble(_keyPreviewDelay, seconds);

  bool getAutoplayPreview({bool fallback = true}) =>
      _prefs.getBool(_keyAutoplayPreview) ?? fallback;
  Future<bool> setAutoplayPreview(bool enabled) =>
      _prefs.setBool(_keyAutoplayPreview, enabled);

  bool getHardwareAccel({bool fallback = true}) =>
      _prefs.getBool(_keyHardwareAccel) ?? fallback;
  Future<bool> setHardwareAccel(bool enabled) =>
      _prefs.setBool(_keyHardwareAccel, enabled);

  bool getLowLatencyMode({bool fallback = true}) =>
      _prefs.getBool(_keyLowLatencyMode) ?? fallback;
  Future<bool> setLowLatencyMode(bool enabled) =>
      _prefs.setBool(_keyLowLatencyMode, enabled);
}
