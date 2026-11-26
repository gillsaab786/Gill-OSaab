// Gill(OS) desktop layout: sidebar, window buttons, compact mode for handhelds.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seedfinder/desktop/gill_desktop.dart';
import 'package:seedfinder/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const GillDesktopApp());
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await store.load();
  });

  testWidgets('wide screen: sidebar with names and Gill(OS) window buttons', (tester) async {
    await pumpAt(tester, const Size(1920, 1080));
    expect(find.text('Torrent Search'), findsOneWidget);
    expect(find.text('Saved'), findsWidgets);
    expect(find.byType(TrafficLights), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byTooltip('Minimise'), findsOneWidget);
  });

  testWidgets('handheld screen: icon-only sidebar', (tester) async {
    await pumpAt(tester, const Size(900, 600));
    expect(find.text('Torrent Search'), findsNothing);
    expect(find.byIcon(CupertinoIcons.bookmark_fill), findsWidgets);
  });

  testWidgets('switching to Settings', (tester) async {
    await pumpAt(tester, const Size(1920, 5000)); // tall, so the whole list is built
    await tester.tap(find.byIcon(CupertinoIcons.gear_solid));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Trackers'), findsWidgets);
    expect(find.text('Match app icon'), findsNothing); // the colour follows Gill(OS) instead
  });
}
