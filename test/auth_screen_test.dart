import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jio_tv_plus_flutter/screens/auth_screen.dart';
import 'package:jio_tv_plus_flutter/services/api_service.dart';
import 'package:jio_tv_plus_flutter/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AuthScreen compiles and renders modern Mobile OTP screen without layout errors', (tester) async {
    // Set typical Android TV resolution: 1920x1080
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storageService = StorageService(prefs);
    final apiService = ApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          apiService: apiService,
          storageService: storageService,
          onLoginSuccess: () {},
        ),
      ),
    );

    expect(find.text('Enter your Mobile Number'), findsOneWidget);
    expect(find.text('Get OTP'), findsOneWidget);
    expect(find.text('Explore as Guest'), findsOneWidget);
  });

  testWidgets('AuthScreen D-Pad navigation and Get OTP button validation', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storageService = StorageService(prefs);
    final apiService = ApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          apiService: apiService,
          storageService: storageService,
          onLoginSuccess: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Initial focus is on Key '1'
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('FirstNumpadKey'));

    // 2. Tapping or pressing Get OTP with empty number triggers validation
    await tester.tap(find.text('Get OTP'));
    await tester.pump();
    expect(find.text('Please enter a complete 10-digit mobile number'), findsOneWidget);

    // 3. Entering digits via on-screen numpad
    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.text('8'));
    await tester.pump();
    await tester.tap(find.text('7'));
    await tester.pump();

    expect(find.textContaining('987'), findsOneWidget);
  });
}
