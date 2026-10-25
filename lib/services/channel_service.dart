import 'dart:async';
import 'stream_proxy_service.dart';
import 'package:flutter/foundation.dart';
import '../models/channel.dart';
import '../models/program.dart';
import 'api_service.dart';
import 'storage_service.dart';

class ChannelService extends ChangeNotifier {
  final ApiService _apiService;
  final StorageService _storageService;
  late final StreamProxyService _streamProxyService;

  List<Channel> _allChannels = [];
  Channel? _currentChannel;
  String _selectedCategory = 'ALL';
  String _selectedLanguage = 'ALL';
  bool _filterOnlyFavorites = false;
  bool _isLoading = false;
  bool _showPremiumChannels = false;

  // EPG Cache: Map<channelId_dayOffset, List<Program>>
  final Map<String, List<Program>> _epgCache = {};

  ChannelService(this._apiService, this._storageService, [StreamProxyService? proxyService]) {
    _streamProxyService = proxyService ?? StreamProxyService(_storageService);
    _showPremiumChannels = _storageService.getShowPremiumChannels(defaultValue: false);
  }

  StreamProxyService get streamProxyService => _streamProxyService;

  bool get showPremiumChannels => _showPremiumChannels;

  Future<void> toggleShowPremiumChannels() async {
    _showPremiumChannels = !_showPremiumChannels;
    await _storageService.setShowPremiumChannels(_showPremiumChannels);
    notifyListeners();
  }

  List<Channel> get allChannels {
    if (_showPremiumChannels) return _allChannels;
    return _allChannels.where((c) => !c.isPremium && c.businessType.toLowerCase() != 'premium').toList();
  }

  List<Channel> get rawChannels => _allChannels;
  Channel? get currentChannel => _currentChannel;
  String get selectedCategory => _selectedCategory;
  String get selectedLanguage => _selectedLanguage;
  bool get filterOnlyFavorites => _filterOnlyFavorites;
  bool get isLoading => _isLoading;

  /// Returns channels grouped into curated categories for modern TV multi-row feed
  Map<String, List<Channel>> get channelsByCategory {
    final Map<String, List<Channel>> grouped = {};
    final channelsList = allChannels;

    // 1. If Favorites exist, put Favorites row at top
    final favs = channelsList.where((c) => c.isFavorite).toList();
    if (favs.isNotEmpty) {
      grouped['Favorites'] = favs;
    }

    // If filtering only favorites, present only user favorites
    if (_filterOnlyFavorites) {
      final Map<String, List<Channel>> favCategoryBuckets = {};
      for (final ch in favs) {
        final cat = ch.category.isNotEmpty ? ch.category : 'General';
        favCategoryBuckets.putIfAbsent(cat, () => []).add(ch);
      }
      for (final entry in favCategoryBuckets.entries) {
        if (!grouped.containsKey(entry.key)) {
          grouped[entry.key] = entry.value;
        }
      }
      return grouped;
    }

    // 2. High-priority Free Channels row
    final freeList = channelsList.where((c) => !c.isPremium).take(20).toList();
    if (freeList.isNotEmpty) {
      grouped['Free Channels'] = freeList;
    }

    // 3. Premium Channels row (when enabled or browsing)
    final premList = _allChannels.where((c) => c.isPremium).take(20).toList();
    if (_showPremiumChannels && premList.isNotEmpty) {
      grouped['Premium Channels'] = premList;
    }

    // 4. Curated Trending & Live Now row
    final featured = channelsList.take(15).toList();
    if (featured.isNotEmpty) {
      grouped['Trending & Live Now'] = featured;
    }

    // 3. High-priority broadcast categories
    const preferredOrder = [
      'Entertainment',
      'News',
      'Sports',
      'Movies',
      'Kids',
      'Music',
      'Infotainment',
      'Devotional',
      'Business News',
      'Lifestyle',
    ];

    final Map<String, List<Channel>> categoryBuckets = {};
    for (final ch in channelsList) {
      final cat = ch.category.isNotEmpty ? ch.category : 'General';
      categoryBuckets.putIfAbsent(cat, () => []).add(ch);
    }

    for (final pref in preferredOrder) {
      final matchingKey = categoryBuckets.keys.firstWhere(
        (k) => k.toLowerCase() == pref.toLowerCase(),
        orElse: () => '',
      );
      if (matchingKey.isNotEmpty && categoryBuckets[matchingKey]!.isNotEmpty) {
        grouped[matchingKey] = categoryBuckets[matchingKey]!;
      }
    }

    for (final entry in categoryBuckets.entries) {
      if (!grouped.containsKey(entry.key)) {
        grouped[entry.key] = entry.value;
      }
    }

    return grouped;
  }

  List<String> get categories {
    final list = <String>['ALL', 'Favorites', 'Free', 'Premium'];
    const preferredOrder = [
      'Entertainment',
      'News',
      'Sports',
      'Movies',
      'Kids',
      'Music',
      'Infotainment',
      'Devotional',
      'Business News',
      'Lifestyle',
      'Educational',
      'Shopping',
    ];
    final found = <String>{};
    for (final ch in allChannels) {
      if (ch.category.isNotEmpty) found.add(ch.category);
    }
    for (final pref in preferredOrder) {
      final match = found.firstWhere((c) => c.toLowerCase() == pref.toLowerCase(), orElse: () => '');
      if (match.isNotEmpty) {
        list.add(match);
        found.remove(match);
      }
    }
    list.addAll(found);
    return list;
  }

  List<String> get languages {
    final list = <String>['ALL'];
    const preferredOrder = [
      'Hindi',
      'English',
      'Marathi',
      'Telugu',
      'Tamil',
      'Bengali',
      'Kannada',
      'Malayalam',
      'Gujarati',
      'Punjabi',
      'Odia',
      'Bhojpuri',
      'Urdu',
      'Assamese',
    ];
    final found = <String>{};
    for (final ch in allChannels) {
      if (ch.language.isNotEmpty) found.add(ch.language);
    }
    for (final pref in preferredOrder) {
      final match = found.firstWhere((l) => l.toLowerCase() == pref.toLowerCase(), orElse: () => '');
      if (match.isNotEmpty) {
        list.add(match);
        found.remove(match);
      }
    }
    list.addAll(found);
    return list;
  }

  List<Channel> searchChannels(String query) {
    final channels = allChannels;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return channels;
    return channels.where((c) {
      return c.channelName.toLowerCase().contains(q) ||
          c.channelNo.toString().contains(q) ||
          c.category.toLowerCase().contains(q) ||
          c.language.toLowerCase().contains(q) ||
          (c.currentProgram?.title.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  List<Channel> get filteredChannels {
    final baseList = (_selectedCategory == 'Premium') ? _allChannels : allChannels;
    return baseList.where((ch) {
      if (_filterOnlyFavorites && !ch.isFavorite) return false;
      if (_selectedCategory == 'Favorites') {
        return ch.isFavorite;
      }
      if (_selectedCategory == 'Free') {
        return !ch.isPremium;
      }
      if (_selectedCategory == 'Premium') {
        return ch.isPremium;
      }
      if (_selectedCategory != 'ALL' && ch.category.toLowerCase() != _selectedCategory.toLowerCase()) {
        return false;
      }
      if (_selectedLanguage != 'ALL' && ch.language.toLowerCase() != _selectedLanguage.toLowerCase()) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> initialize() async {
    _isLoading = true;
    unawaited(_streamProxyService.start());
    notifyListeners();

    final favorites = _storageService.getFavorites();
    _allChannels = await _apiService.fetchChannels();

    for (final ch in _allChannels) {
      if (favorites.contains(ch.channelId)) {
        ch.isFavorite = true;
      }
    }

    final lastChannelId = _storageService.getLastChannelId(fallback: _allChannels.isNotEmpty ? _allChannels.first.channelId : '104');
    _currentChannel = _allChannels.firstWhere(
      (c) => c.channelId == lastChannelId,
      orElse: () => _allChannels.isNotEmpty ? _allChannels.first : _allChannels.first,
    );

    _isLoading = false;
    notifyListeners();
  }

  void selectCategory(String category) {
    _selectedCategory = category;
    if (category == 'Favorites') {
      _filterOnlyFavorites = true;
    } else {
      _filterOnlyFavorites = false;
    }
    notifyListeners();
  }

  void selectLanguage(String language) {
    _selectedLanguage = language;
    notifyListeners();
  }

  @visibleForTesting
  void setChannelsForTesting(List<Channel> channels) {
    _allChannels = List.from(channels);
    if (_allChannels.isNotEmpty) {
      _currentChannel = _allChannels.first;
    }
    notifyListeners();
  }

  void toggleFavoritesFilter() {
    _filterOnlyFavorites = !_filterOnlyFavorites;
    notifyListeners();
  }

  void tuneChannel(Channel channel) {
    _currentChannel = channel;
    _storageService.setLastChannelId(channel.channelId);
    notifyListeners();
  }

  void tuneToChannelNo(int channelNo) {
    final found = _allChannels.firstWhere(
      (c) => c.channelNo == channelNo,
      orElse: () => _currentChannel ?? _allChannels.first,
    );
    tuneChannel(found);
  }

  void nextChannel() {
    if (_allChannels.isEmpty || _currentChannel == null) return;
    final currentIndex = _allChannels.indexWhere((c) => c.channelId == _currentChannel!.channelId);
    final nextIndex = (currentIndex + 1) % _allChannels.length;
    tuneChannel(_allChannels[nextIndex]);
  }

  void previousChannel() {
    if (_allChannels.isEmpty || _currentChannel == null) return;
    final currentIndex = _allChannels.indexWhere((c) => c.channelId == _currentChannel!.channelId);
    final prevIndex = (currentIndex - 1 + _allChannels.length) % _allChannels.length;
    tuneChannel(_allChannels[prevIndex]);
  }

  Future<void> toggleFavorite(Channel channel) async {
    await _storageService.toggleFavorite(channel.channelId);
    channel.isFavorite = !channel.isFavorite;
    notifyListeners();
  }

  Future<List<Program>> getEpgForChannel(String channelId, {int dayOffset = 0}) async {
    final cacheKey = '${channelId}_$dayOffset';
    if (_epgCache.containsKey(cacheKey)) {
      return _epgCache[cacheKey]!;
    }
    final epg = await _apiService.fetchChannelEpg(channelId: channelId, dayOffset: dayOffset);
    _epgCache[cacheKey] = epg;
    return epg;
  }

  /// Resolve stream playback URL (Live or Catchup) via upstream Playback API
  Future<String> resolvePlaybackUrl(Channel channel, {Program? program}) async {
    final accessToken = _storageService.getAccessToken();
    final ssoToken = _storageService.getSsoToken();
    final crmId = _storageService.getCrmId();
    final uniqueId = _storageService.getUniqueId();

    debugPrint('==================== [ChannelService] Resolving Playback ====================');
    debugPrint('Channel: [${channel.channelNo}] ${channel.channelName} (ID: ${channel.channelId})');
    debugPrint('Auth Status: ${_storageService.isAuthenticated ? "LOGGED IN (ES256 Token: ${accessToken != null ? "Present" : "Missing"}, HS256 Token: ${ssoToken != null ? "Present" : "Missing"})" : "UNAUTHENTICATED (Guest Mode)"}');

    if (program != null && program.isPast) {
      debugPrint('[ChannelService] Step 1: Requesting Catchup stream for "${program.title}" (${program.startTime} - ${program.endTime})...');
      final resolved = await _apiService.getPlaybackUrl(
        channelId: channel.channelId,
        streamType: 'Catchup',
        accessToken: accessToken,
        ssoToken: ssoToken,
        crmId: crmId,
        uniqueId: uniqueId,
        startTime: program.startTime,
        endTime: program.endTime,
      );
      if (resolved != null && resolved.isNotEmpty) {
        debugPrint('✅ [ChannelService] Catchup stream successfully resolved: $resolved');
        return _streamProxyService.buildPlayableUrl(
          rawMasterUrl: resolved,
          channelId: channel.channelId,
        );
      }
    } else {
      // 1. Try Live stream from JioTV Playback API
      debugPrint('[ChannelService] Step 1: Requesting tokenized stream from JioTV Playback API...');
      final resolved = await _apiService.getPlaybackUrl(
        channelId: channel.channelId,
        streamType: 'Live',
        accessToken: accessToken,
        ssoToken: ssoToken,
        crmId: crmId,
        uniqueId: uniqueId,
      );
      if (resolved != null && resolved.isNotEmpty) {
        debugPrint('✅ [ChannelService] Live stream successfully resolved: $resolved');
        return _streamProxyService.buildPlayableUrl(
          rawMasterUrl: resolved,
          channelId: channel.channelId,
        );
      }
    }

    // 2. Channel direct stream URL if present and not mock
    if (channel.streamUrl.isNotEmpty &&
        !channel.streamUrl.contains('mux.dev') &&
        !channel.streamUrl.contains('oceans.mp4') &&
        !channel.streamUrl.contains('big_buck_bunny')) {
      debugPrint('ℹ️ [ChannelService] Step 2: Using channel predefined broadcast URL: ${channel.streamUrl}');
      return channel.streamUrl;
    }

    // 3. Upstream JioTV COD CDN live HLS stream for this channel
    final cleanName = channel.channelName
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
    final cdnFallback = 'https://jiotvcod.cdn.jio.com/bpk-tv/${cleanName}_MOB/Live/index.m3u8';
    debugPrint('⚠️ [ChannelService] Step 3: Upstream Playback API returned null. Falling back to direct CDN: $cdnFallback');
    debugPrint('💡 [ChannelService] Notice: Direct bpk-tv CDN streams require Akamai EdgeAuth token (__hdnea__). Direct playback without tokens will trigger HTTP 403 Forbidden.');
    return _streamProxyService.buildPlayableUrl(
      rawMasterUrl: cdnFallback,
      channelId: channel.channelId,
    );
  }
@override
  void dispose() {
    unawaited(_streamProxyService.stop());
    super.dispose();
  }
}
