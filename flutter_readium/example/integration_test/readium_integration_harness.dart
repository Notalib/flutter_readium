import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fixtures.dart';
import 'web_resource_probe.dart' if (dart.library.js_interop) 'web_resource_probe_web.dart';

/// Budget for the first textLocator/status emission after mounting a reader widget. Each mount
/// launches a fresh WebContent process, and on the 3-core CI simulator a launch has hung for 59s
/// and 83s mid-run (seen in the sim logarchive), long after groups/warm_up.dart warmed WebKit.
/// Two mounts in one test must still fit the 300s per-test `--timeout`, hence 120s and not more.
const firstMountTimeout = Duration(seconds: 120);

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
}) => _expectAudioState(
  reader,
  enable: enable,
  matches: (state) => state.state == TimebasedState.playing && state.currentLocator != null,
  timeout: timeout,
  reason: 'Playback did not reach playing with a current locator',
);

/// Asserts that a timebased session actually starts, without requiring sound.
///
/// Chrome blocks autoplay in the web test harness, so `playing` is unreachable there.
/// A state event carrying a `currentLocator` is the honest signal instead: it can only
/// be emitted once a navigator exists, which means the cue parser produced items.
/// A publication whose cues were all dropped emits nothing at all.
Future<void> expectAudioSessionStarts(
  FlutterReadium reader, {
  required Future<void> Function() enable,
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) => _expectAudioState(
  reader,
  enable: enable,
  matches: (state) => state.currentLocator != null,
  timeout: timeout,
  reason: reason ?? 'audioEnable produced no playback state with a current locator',
);

Future<void> _expectAudioState(
  FlutterReadium reader, {
  required Future<void> Function() enable,
  required bool Function(ReadiumTimebasedState) matches,
  required Duration timeout,
  required String reason,
}) async {
  final reachedState = Completer<void>();
  // Capture events during enable/play, and cancel even when either call fails.
  final sub = reader.onTimebasedPlayerStateChanged.listen((state) {
    if (matches(state) && !reachedState.isCompleted) reachedState.complete();
  });
  try {
    await timedPhase('audio enable', enable);
    await timedPhase('audio play', () => reader.play(null));
    await timedPhase(
      'audio state',
      () => reachedState.future.timeout(timeout, onTimeout: () => fail(reason)),
      timeout: timeout + const Duration(seconds: 1),
    );
    await timedPhase('audio pause', reader.pause);
  } finally {
    await sub.cancel();
  }
}

Future<T> timedPhase<T>(
  String name,
  Future<T> Function() action, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final watch = Stopwatch()..start();
  try {
    return await action().timeout(
      timeout,
      onTimeout: () => fail('$name did not complete within $timeout'),
    );
  } finally {
    debugPrint('integration phase "$name": ${watch.elapsedMilliseconds}ms');
  }
}

/// Observes the full window on success, but fails as soon as a violation is recorded.
Future<void> expectConditionHolds(
  bool Function() predicate, {
  required Duration duration,
  required String reason,
}) async {
  final watch = Stopwatch()..start();
  while (true) {
    expect(predicate(), isTrue, reason: reason);
    final remaining = duration - watch.elapsed;
    if (remaining <= Duration.zero) return;
    await Future<void>.delayed(
      remaining < const Duration(milliseconds: 100) ? remaining : const Duration(milliseconds: 100),
    );
  }
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
  if (reason != null) {
    debugPrint('integration wait: ${DateTime.now().difference(start).inMilliseconds}ms | $reason');
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
