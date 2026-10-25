import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jio_tv_plus_flutter/models/channel.dart';
import 'package:jio_tv_plus_flutter/screens/account_screen.dart';
import 'package:jio_tv_plus_flutter/screens/home_screen.dart';
import 'package:jio_tv_plus_flutter/services/api_service.dart';
import 'package:jio_tv_plus_flutter/services/channel_service.dart';
import 'package:jio_tv_plus_flutter/services/storage_service.dart';
import 'package:jio_tv_plus_flutter/theme/tv_dimensions.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Focus border dimensions and non-cropping physics', () {
    test('TvDimensions focus border width and scale are calibrated to prevent clipping', () {
      expect(TvDimensions.focusBorderWidth, 2.0);
      expect(TvDimensions.focusScaleStandard, 1.02);
      expect(TvDimensions.focusScaleLarge, 1.02);
    });
  });

  group('StorageService preview delay settings', () {
    test('Default delay is 1.0s and can be adjusted', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      expect(storage.getPreviewAutoplayDelay(), 1.0);
      expect(storage.getAutoplayPreview(), true);

      await storage.setPreviewAutoplayDelay(2.0);
      expect(storage.getPreviewAutoplayDelay(), 2.0);

      await storage.setAutoplayPreview(false);
      expect(storage.getAutoplayPreview(), false);
    });
  });

  group('Settings Screen (AccountScreen) 2-Pane UI', () {
    testWidgets('Renders 2-pane settings layout with delay configuration and NO storage tab', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'jiotv_mobile_number': '9876543210'});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final api = ApiService();
      final channelService = ChannelService(api, storage);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountScreen(
              storageService: storage,
              channelService: channelService,
              onSignOut: () {},
              onBack: () {},
            ),
          ),
        ),
      );

      // Verify Left Pane Title
      expect(find.text('Settings'), findsOneWidget);

      // Verify Section Tiles
      expect(find.text('Playback & Preview'), findsWidgets);
      expect(find.text('Account'), findsWidgets);
      expect(find.text('Channels & Guide'), findsOneWidget);
      expect(find.text('Fire TV Live Guide'), findsOneWidget);
      expect(find.text('System & Diagnostics'), findsOneWidget);

      // Crucial requirement: No "Storage" tab
      expect(find.text('Storage space'), findsNothing);

      // Verify delay configuration row under Playback & Preview
      expect(find.text('Preview Autoplay Delay'), findsOneWidget);
      expect(find.text('1.0s'), findsOneWidget);

      // Tap on delay to cycle from 1.0s -> 1.5s
      await tester.tap(find.text('Preview Autoplay Delay'));
      await tester.pumpAndSettle();

      expect(find.text('1.5s'), findsOneWidget);
      expect(storage.getPreviewAutoplayDelay(), 1.5);
    });
  });

  group('HomeScreen Fixed Container & Row-Swapping Stage', () {
    testWidgets('Renders Fixed Stage: Container, Categories, Category Name, Channel row', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final api = ApiService();
      final channelService = ChannelService(api, storage);

      final ch1 = Channel(
        channelId: '104',
        channelNo: 104,
        channelName: 'Aaj Tak',
        logoUrl: '',
        streamUrl: 'https://jiotvcod.cdn.jio.com/live/104.m3u8',
        category: 'News',
        language: 'Hindi',
      );
      final ch2 = Channel(
        channelId: '144',
        channelNo: 144,
        channelName: 'Colors HD',
        logoUrl: '',
        streamUrl: 'https://jiotvcod.cdn.jio.com/live/144.m3u8',
        category: 'Entertainment',
        language: 'Hindi',
      );
      channelService.setChannelsForTesting([ch1, ch2]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              channelService: channelService,
              storageService: storage,
              onOpenPlayer: (_) {},
              onNavigate: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Fixed Hero Container shows channel info & Watch Live button immediately
      expect(find.text('Watch Live'), findsOneWidget);
      expect(find.text('Add to Favorites'), findsOneWidget);
      expect(find.text('More Info'), findsOneWidget);

      // Category channel cards are rendered
      expect(find.text('Trending & Live Now'), findsWidgets);
      expect(find.text('Aaj Tak'), findsWidgets);

      // Pressing Down on D-Pad swaps Current Row to Next Category in-place without page scrolling
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 200));

      // Entertainment is now the current category row
      expect(find.text('Entertainment'), findsWidgets);
      expect(find.text('Colors HD'), findsWidgets);

      // Pressing Up on D-Pad returns to Previous Category in-place
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Trending & Live Now'), findsWidgets);
      expect(find.text('Aaj Tak'), findsWidgets);
    });
  });
}
