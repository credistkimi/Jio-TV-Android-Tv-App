import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jio_tv_plus_flutter/models/channel.dart';
import 'package:jio_tv_plus_flutter/models/program.dart';
import 'package:jio_tv_plus_flutter/screens/player_screen.dart';
import 'package:jio_tv_plus_flutter/services/api_service.dart';
import 'package:jio_tv_plus_flutter/services/channel_service.dart';
import 'package:jio_tv_plus_flutter/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockChannel = Channel(
    channelId: '1006',
    channelName: 'ABP News India',
    channelNo: 1006,
    category: 'News',
    language: 'Hindi',
    isHd: true,
    streamUrl: 'https://jiotvcod.cdn.jio.com/bpk-tv/ABP_News_MOB/Live/index.m3u8',
    logoUrl: 'https://jiotv.catchup.cdn.jio.com/dare_images/images/ABP_News.png',
  );

  final mockSimilar = Channel(
    channelId: '1014',
    channelName: 'DD News',
    channelNo: 1014,
    category: 'News',
    language: 'Hindi',
    streamUrl: 'https://jiotvcod.cdn.jio.com/bpk-tv/DD_News_MOB/Live/index.m3u8',
    logoUrl: 'https://jiotv.catchup.cdn.jio.com/dare_images/images/DD_News.png',
  );

  final mockProgram = Program(
    programId: 'p1',
    channelId: '1006',
    title: 'ABP News India Live Broadcast',
    synopsis: 'Live daily prime news and political debate analysis',
    startTime: DateTime.now().subtract(const Duration(minutes: 15)),
    endTime: DateTime.now().add(const Duration(minutes: 15)),
  );

  testWidgets('PlayerScreen renders full TV playback layout matching reference design', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final api = ApiService();
    final channelService = ChannelService(api, storage);
    channelService.setChannelsForTesting([mockChannel, mockSimilar]);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          initialChannel: mockChannel,
          targetProgram: mockProgram,
          channelService: channelService,
          onBack: () {},
        ),
      ),
    );
    await tester.pump();

    // 1. Top Bar Elements
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('TV Guide'), findsOneWidget);
    expect(find.text('Channel Info'), findsOneWidget);

    // 2. Middle-Left Channel & Program Info
    expect(find.text('● LIVE'), findsWidgets);
    expect(find.text('1006: ABP News India'), findsOneWidget);
    expect(find.text('ABP News India Live Broadcast'), findsWidgets);
    expect(find.textContaining('News  |  Hindi  |  U/A 7+'), findsOneWidget);

    // 3. Center Action Controls
    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Subtitles'), findsOneWidget);
    expect(find.text('Guide'), findsOneWidget);

    // 4. Timeline Section
    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('PlayerScreen D-Pad 3-zone navigation allows accessing all controls without traps', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final api = ApiService();
    final channelService = ChannelService(api, storage);
    channelService.setChannelsForTesting([mockChannel, mockSimilar]);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          initialChannel: mockChannel,
          targetProgram: mockProgram,
          channelService: channelService,
          onBack: () {},
        ),
      ),
    );
    await tester.pump();

    // 1. Initial default focus on Play/Pause (Zone 2 centerpiece)
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('PlayerPlayPause'));

    // 2. D-pad Up moves focus to Top Bar (Zone 1)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('TopBack'));

    // 3. D-pad Right traverses within Top Bar: Back -> TV Guide -> Channel Info
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('TopTvGuide'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('TopChannelInfo'));

    // 4. D-pad Down from Top Bar returns to Controls Row (Zone 2)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('PlayerQuality'));

    // 5. D-pad Left moves across Controls Row: Quality -> Volume -> Next -> PlayPause
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('PlayerVolume'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('PlayerNext'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('PlayerPlayPause'));

    // 6. D-pad Down from Controls Row moves to Similar Channels Carousel (Zone 3)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('CarouselChannel'));

    // 7. D-pad Up from Carousel returns cleanly to Controls Row (Zone 2)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('PlayerPlayPause'));
  });
}
