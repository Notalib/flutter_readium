import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ReadiumAudioRoutePicker renders nothing off iOS', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: ReadiumAudioRoutePicker()),
      ),
    );

    expect(tester.getSize(find.byType(ReadiumAudioRoutePicker)), Size.zero);
    expect(find.byType(UiKitView), findsNothing);
  });

  group('on iOS', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async => null,
      );
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      );
    });

    Widget picker(Color color) => MaterialApp(
      home: Center(
        child: ReadiumAudioRoutePicker(color: color, activeColor: const Color(0xFF00FF00)),
      ),
    );

    testWidgets('hosts the native picker with ARGB tint params', (tester) async {
      await tester.pumpWidget(picker(const Color(0x80FF0000)));

      final view = tester.widget<UiKitView>(find.byType(UiKitView));
      expect(view.viewType, 'dk.nota.flutter_readium/audio-route-picker');
      expect(view.creationParams, {'tintColor': 0x80FF0000, 'activeTintColor': 0xFF00FF00});
      // Restore before the binding's end-of-test platform check.
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('recreates the native view when the tint changes', (tester) async {
      await tester.pumpWidget(picker(const Color(0xFFFF0000)));
      final firstKey = tester.widget<UiKitView>(find.byType(UiKitView)).key;

      await tester.pumpWidget(picker(const Color(0xFF0000FF)));
      final secondKey = tester.widget<UiKitView>(find.byType(UiKitView)).key;

      expect(secondKey, isNot(firstKey));
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
