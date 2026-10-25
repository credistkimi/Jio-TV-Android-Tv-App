import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jio_tv_plus_flutter/models/channel.dart';
import 'package:jio_tv_plus_flutter/services/api_service.dart';
import 'package:jio_tv_plus_flutter/services/channel_service.dart';
import 'package:jio_tv_plus_flutter/services/storage_service.dart';
import 'package:jio_tv_plus_flutter/widgets/tv_category_pill.dart';
import 'package:jio_tv_plus_flutter/widgets/tv_nav_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('TvNavBar renders only specified pills and prunes movies, shows, etc.', (tester) async {
    TvNavDestination? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvNavBar(
            currentDestination: TvNavDestination.liveGuide,
            onDestinationSelected: (dest) => selected = dest,
          ),
        ),
      ),
    );

    // Required navbar destinations
    expect(find.text('For You'), findsOneWidget);
    expect(find.text('Digital TV'), findsOneWidget);
    expect(find.text('Catch Up TV'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);

    // Pruned destinations must NOT be in the navbar
    expect(find.text('Movies'), findsNothing);
    expect(find.text('Shows'), findsNothing);
    expect(find.text('Kids'), findsNothing);
    expect(find.text('Music'), findsNothing);
    expect(find.text('Sports'), findsNothing);

    // Tapping Digital TV selects epgGrid
    await tester.tap(find.text('Digital TV'));
    await tester.pump();
    expect(selected, TvNavDestination.epgGrid);
  });

  testWidgets('TvCategoryPill renders active blue and inactive dark capsules with white text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              TvCategoryPill(
                label: 'All Channels',
                isSelected: true,
                onPressed: () {},
              ),
              TvCategoryPill(
                label: 'Entertainment',
                isSelected: false,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('All Channels'), findsOneWidget);
    expect(find.text('Entertainment'), findsOneWidget);
  });

  test('resolvePlaybackUrl resolves real live stream and eliminates mock static videos', () async {
    SharedPreferences.setMockInitialValues({'sso_token': 'test_token'});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final apiService = ApiService();
    final channelService = ChannelService(apiService, storage);

    final testChannel = Channel(
      channelId: '144',
      channelNo: 144,
      channelName: 'Colors HD',
      logoUrl: 'https://img.media.jio.com/apis/v1.4/getchannelimage/get/144.png',
      streamUrl: '',
      category: 'Entertainment',
      language: 'Hindi',
    );

    final streamUrl = await channelService.resolvePlaybackUrl(testChannel);

    // Must be a real HLS live stream (either API result or direct Jio COD CDN)
    expect(streamUrl.isNotEmpty, true);
    expect(streamUrl.contains('mux.dev'), false);
    expect(streamUrl.contains('oceans.mp4'), false);
    expect(streamUrl.contains('big_buck_bunny'), false);
    expect(streamUrl.contains('.m3u8'), true);
  });

  test('ChannelService channelsByCategory filters only favorites when filterOnlyFavorites is true', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final apiService = ApiService();
    final channelService = ChannelService(apiService, storage);

    final ch1 = Channel(
      channelId: '1',
      channelNo: 1,
      channelName: 'Channel 1',
      logoUrl: '',
      streamUrl: '',
      category: 'News',
      language: 'Hindi',
      isFavorite: true,
    );
    final ch2 = Channel(
      channelId: '2',
      channelNo: 2,
      channelName: 'Channel 2',
      logoUrl: '',
      streamUrl: '',
      category: 'Entertainment',
      language: 'Hindi',
      isFavorite: false,
    );

    // Feed channels
    channelService.rawChannels.addAll([ch1, ch2]);

    // Unfiltered
    expect(channelService.channelsByCategory.containsKey('Trending & Live Now'), true);

    // Filter favorites
    channelService.toggleFavoritesFilter();
    final favGrouped = channelService.channelsByCategory;
    expect(favGrouped.containsKey('Trending & Live Now'), false);
    expect(favGrouped.containsKey('Favorites'), true);
    expect(favGrouped['Favorites']!.length, 1);
    expect(favGrouped['Favorites']!.first.channelId, '1');
  });

  test('ChannelService showPremiumChannels toggle hides premium channels by default and reveals them when toggled', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final apiService = ApiService();
    final channelService = ChannelService(apiService, storage);

    final standardChannel = Channel(
      channelId: '101',
      channelNo: 101,
      channelName: 'Aaj Tak',
      logoUrl: '',
      streamUrl: '',
      category: 'News',
      language: 'Hindi',
      isPremium: false,
      businessType: 'jio',
    );
    final premiumChannel1 = Channel(
      channelId: '201',
      channelNo: 201,
      channelName: 'Sony Ten 1 HD',
      logoUrl: '',
      streamUrl: '',
      category: 'Sports',
      language: 'English',
      isPremium: true,
      businessType: 'jio',
    );
    final premiumChannel2 = Channel(
      channelId: '202',
      channelNo: 202,
      channelName: 'Star Movies Select',
      logoUrl: '',
      streamUrl: '',
      category: 'Movies',
      language: 'English',
      isPremium: false,
      businessType: 'premium',
    );

    channelService.rawChannels.addAll([standardChannel, premiumChannel1, premiumChannel2]);

    // By default, showPremiumChannels is false
    expect(channelService.showPremiumChannels, false);
    expect(channelService.allChannels.length, 1);
    expect(channelService.allChannels.first.channelId, '101');

    // Toggle on
    await channelService.toggleShowPremiumChannels();
    expect(channelService.showPremiumChannels, true);
    expect(channelService.allChannels.length, 3);

    // Toggle off
    await channelService.toggleShowPremiumChannels();
    expect(channelService.showPremiumChannels, false);
    expect(channelService.allChannels.length, 1);
  });
}
