import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fixtures.dart';
import 'web_resource_probe.dart' if (dart.library.js_interop) 'web_resource_probe_web.dart';

/// Budget for the first textLocator/status emission after mounting a reader widget:
/// each mount launches a fresh platform-view webview, and CI runner speed varies
/// 2x+ run to run (a 3s warm-up on a fast runner vs. 22s+ on a slow one). 45s is the
/// ceiling already proven safe for a cold CI simulator by groups/warm_up.dart;
/// reuse it everywhere instead of guessing a fresh number per call site.
const firstMountTimeout = Duration(seconds: 60);

class ReadiumIntegrationHarness {
  final readium = FlutterReadium();
  late Map<String, String> fixturePaths;

  Future<void> loadFixtures() async {
    fixturePaths = await loadFixturePaths();
  }

  String fixturePath(String key, {String? reason}) {
    final path = fixturePaths[key];
    expect(path, isNotNull, reason: reason ?? 'Fixture $key missing from asset bundle');
    return path!;
  }

  Future<void> closePublication() => readium.closePublication();
}

Widget bareReaderApp(Publication pub, {Locator? initialLocator}) => MaterialApp(
  home: Scaffold(
    body: ReadiumReaderWidget(
      publication: pub,
      initialLocator: initialLocator,
    ),
  ),
);

ReadiumReaderWidget fullyWiredReaderWidget(Publication pub) => ReadiumReaderWidget(
  publication: pub,
  shouldShowControls: ValueNotifier(true),
  allowedDefaultActions: const {
    DefaultSelectionAction.copy,
    DefaultSelectionAction.share,
    DefaultSelectionAction.translate,
  },
  selectionActions: const [
    SelectionAction(id: 'highlight', title: 'Highlight'),
    SelectionAction(id: 'note', title: 'Add Note'),
  ],
  onExternalLinkActivated: (_) {},
  onTextSelected: (_) {},
  onSelectionAction: (_) {},
  onDecorationInteraction: (_) {},
);

Future<void> mountFullyWiredAndSmokeTest(
  ReadiumIntegrationHarness harness,
  WidgetTester tester,
  Publication pub, {
  required String reason,
}) async {
  final locators = <Locator>[];
  final sub = harness.readium.onTextLocatorChanged.listen(locators.add);
  addTearDown(sub.cancel);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: fullyWiredReaderWidget(pub)),
    ),
  );
  await waitWithPump(
    tester,
    () => locators.isNotEmpty,
    timeout: firstMountTimeout,
    reason: reason,
  );

  // Exercise the gesture-driven notifyUserNavigation path: a plain center-tap
  // toggles controls instead, only a drag past the swipe threshold reaches it.
  await tester.drag(find.byType(ReadiumReaderWidget), const Offset(20, 0));
  await tester.pump();

  await tester.pumpWidget(const SizedBox());
}

Future<void> expectNativeFileImageDecodes(String url, {required String href}) async {
  expect(
    Uri.parse(url).isScheme('file'),
    isTrue,
    reason: 'Expected a file:// URL on native platforms, got: $url',
  );

  final buffer = await ui.ImmutableBuffer.fromFilePath(Uri.parse(url).toFilePath());
  final codec = await ui.instantiateImageCodecFromBuffer(buffer);
  final frame = await codec.getNextFrame();
  expect(
    frame.image.width > 0 && frame.image.height > 0,
    isTrue,
    reason: 'Cached file for $href did not decode to a valid image',
  );
}

Future<void> expectWebResourceUrlLoads(String url, {required String href}) async {
  final uri = Uri.parse(url);
  expect(
    uri.path,
    startsWith('/test-fixtures/'),
    reason: 'Expected a same-origin test fixture URL for $href, got: $url',
  );

  final lengthInBytes = await loadWebResourceBytes(url);
  expect(
    lengthInBytes,
    greaterThan(0),
    reason: 'Web resource URL for $href did not load any bytes',
  );
}

Future<void> exerciseAudioPlayback(
  FlutterReadium reader, {
  required Future<void> Function() enable,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final reachedPlaying = reader.onTimebasedPlayerStateChanged
      .firstWhere((s) => s.state == TimebasedState.playing && s.currentLocator != null)
      .timeout(timeout);

  await enable();
  await reader.play(null);

  final playingState = await reachedPlaying;
  expect(
    playingState.currentLocator,
    isNotNull,
    reason: 'A playing state event should carry the current playback locator',
  );

  await reader.pause();
}

Future<void> waitUntil(
  bool Function() predicate, {
  required Duration timeout,
  String? reason,
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason ?? 'Condition did not become true within $timeout');
    }
    await Future<void>.delayed(pollInterval);
  }
}

/// Pumps until [predicate] holds. On timeout it fails the test, or just returns if
/// [failOnTimeout] is false — either way it logs `waitWithPump TIMEOUT`. Pass `false` only
/// where the wait is best-effort and a real test asserts the condition elsewhere.
Future<void> waitWithPump(
  WidgetTester tester,
  bool Function() predicate, {
  required Duration timeout,
  String? reason,
  String Function()? diagnostics,
  bool failOnTimeout = true,
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final start = DateTime.now();
  final deadline = start.add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      final elapsedMs = DateTime.now().difference(start).inMilliseconds;
      final diag = diagnostics != null ? ' | ${diagnostics()}' : '';
      final base = reason ?? 'Condition did not become true within $timeout';
      debugPrint('waitWithPump TIMEOUT after ${elapsedMs}ms: $base$diag');
      if (failOnTimeout) {
        fail('$base (waited ${elapsedMs}ms)$diag');
      }
      return;
    }
    await tester.pump(pollInterval);
  }
}

Future<void> waitForListStable<T>(
  WidgetTester tester,
  List<T> list, {
  Duration stableFor = const Duration(milliseconds: 600),
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  var lastLength = list.length;
  var stableSince = DateTime.now();
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(pollInterval);
    if (list.length != lastLength) {
      lastLength = list.length;
      stableSince = DateTime.now();
    } else if (DateTime.now().difference(stableSince) >= stableFor) {
      return;
    }
  }
}

bool isAndroid() => defaultTargetPlatform == TargetPlatform.android;
