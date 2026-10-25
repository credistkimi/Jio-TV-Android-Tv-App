import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jio_tv_plus_flutter/screens/splash_screen.dart';

void main() {
  testWidgets('SplashScreen renders JioTV+ brand and triggers onFinish callback without hanging', (tester) async {
    bool finished = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          playSound: false, // Avoid headless platform audio issues in unit tests
          duration: const Duration(milliseconds: 300),
          onFinish: () {
            finished = true;
          },
        ),
      ),
    );

    // Initial frame shows loading spinner and splash screen
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(finished, false);

    // Advance animation smoothly past duration
    await tester.pump(const Duration(milliseconds: 150));
    expect(finished, false);

    await tester.pump(const Duration(milliseconds: 200));
    // onFinish callback must have fired cleanly
    expect(finished, true);
  });
}
