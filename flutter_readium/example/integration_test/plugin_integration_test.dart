// Integration tests that open one fixture for each publication type
// (EPUB, WebPub with media overlays, audiobook) on the real native toolkit
// and verify the Dart side receives a well-formed [Publication].
//
// These tests exercise the Dart -> native -> Dart contract that pure Dart
// unit tests cannot reach. They run on iOS and Android via the example app.

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_readium_example/utils/publication_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> fixturePaths;
  final reader = FlutterReadium();

  setUpAll(() async {
    final pubs = await PublicationUtils.moveAssetPublicationsToReadiumStorage();
    fixturePaths = {for (final pub in pubs) p.basename(pub): pub};
  });

  tearDown(() async {
    await reader.closePublication();
  });

  test('opens EPUB succesfully', () async {
    final path = fixturePaths['moby_dick.epub'];
    expect(path, isNotNull, reason: 'Fixture moby_dick.epub missing from asset bundle');

    final pub = await reader.openPublication(path!);

    expect(pub.metadata.title, isNotEmpty);
    expect(pub.readingOrder, isNotEmpty);
    expect(pub.containsMediaOverlays, isFalse, reason: 'Plain EPUB should not report media overlays');
  });

  test('opens EPUB and enables TTS', () async {
    final path = fixturePaths['moby_dick.epub'];
    expect(path, isNotNull, reason: 'Fixture moby_dick.epub missing from asset bundle');

    await reader.openPublication(path!);

    await _exerciseAudioPlayback(
      reader,
      enable: () => reader.ttsEnable(TTSPreferences(speed: 1.0)),
      // First-time TTS engine init on Android can be slow.
      timeout: const Duration(seconds: 10),
    );
  });

  testWidgets('opens and navigates forward in EPUB and receives a new textLocator', (tester) async {
    final path = fixturePaths['moby_dick.epub'];
    expect(path, isNotNull, reason: 'Fixture moby_dick.epub missing from asset bundle');

    final pub = await reader.openPublication(path!);

    final locators = <Locator>[];
    ReadiumReaderStatus? readerStatus;
    final readerStatusSub = reader.onReaderStatusChanged.listen((status) => readerStatus = status);
    final textLocatorSub = reader.onTextLocatorChanged.listen(locators.add);
    addTearDown(textLocatorSub.cancel);
    addTearDown(readerStatusSub.cancel);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReadiumReaderWidget(publication: pub)),
      ),
    );

    // The widget mounts the native navigator, which emits the first
    // textLocator event once the first page has rendered. We must keep
    // pumping frames during the wait, otherwise the platform view's
    // WKWebView/Android surface stalls and never finishes loading.
    await _waitWithPump(
      tester,
      () => locators.isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'ReadiumReaderWidget never emitted an initial textLocator',
    );
    final initialLocator = locators.last;

    // The reader should have emitted ready now that we have received the first Locator.
    expect(
      readerStatus,
      equals(ReadiumReaderStatus.ready),
      reason: 'Reader should be in ready status after widget has mounted',
    );

    await reader.goForward();

    await _waitWithPump(
      tester,
      () => locators.last != initialLocator,
      timeout: const Duration(seconds: 15),
      reason: 'goForward() did not produce a new textLocator',
    );
    expect(
      locators.last,
      isNot(equals(initialLocator)),
      reason: 'goForward() should emit a textLocator distinct from the initial one.',
    );

    // Unmount the platform view before closePublication() runs in tearDown.
    await tester.pumpWidget(const SizedBox());
  });

  test('webpub with media-overlays plays audio', () async {
    final path = fixturePaths['38533_overlay_preview.webpub'];
    expect(path, isNotNull, reason: 'Fixture 38533_overlay_preview.webpub missing from asset bundle');

    final pub = await reader.openPublication(path!);

    expect(pub.readingOrder, isNotEmpty);
    expect(pub.containsMediaOverlays, isTrue, reason: 'Overlay webpub should report media overlays');

    await _exerciseAudioPlayback(reader, enable: () => reader.audioEnable(prefs: AudioPreferences(speed: 1.0)));
  });

  test('audiobooks plays audio', () async {
    final path = fixturePaths['38533.audiobook'];
    expect(path, isNotNull, reason: 'Fixture 38533.audiobook missing from asset bundle');

    final pub = await reader.openPublication(path!);

    expect(pub.readingOrder, isNotEmpty);
    expect(
      pub.conformsToReadiumAudiobook,
      isTrue,
      reason: 'Audiobook fixture should conform to the Readium audiobook profile',
    );

    await _exerciseAudioPlayback(reader, enable: () => reader.audioEnable(prefs: AudioPreferences(speed: 1.0)));
  });

  // ---------------------------------------------------------------------------
  // Error path
  // ---------------------------------------------------------------------------

  test('openPublication throws ReadiumException for an invalid path', () async {
    await expectLater(reader.openPublication('/does-not-exist/no-such.epub'), throwsA(isA<ReadiumException>()));
  });

  // ---------------------------------------------------------------------------
  // EPUB navigation & state
  // ---------------------------------------------------------------------------

  group('EPUB navigation and state', () {
    test('searchInPublication returns hits for a common word in Moby-Dick', () async {
      final path = fixturePaths['moby_dick.epub'];
      expect(path, isNotNull, reason: 'Fixture moby_dick.epub missing from asset bundle');

      await reader.openPublication(path!);

      final results = await reader.searchInPublication('whale');
      expect(results, isNotEmpty, reason: '"whale" should yield matches in Moby-Dick');
      expect(results.first.locator.href, isNotEmpty);
    });

    testWidgets('goToLocator round-trips back to a saved position', (tester) async {
      final path = fixturePaths['moby_dick.epub'];
      expect(path, isNotNull, reason: 'Fixture moby_dick.epub missing from asset bundle');

      final pub = await reader.openPublication(path!);

      final locators = <Locator>[];
      final sub = reader.onTextLocatorChanged.listen(locators.add);
      addTearDown(sub.cancel);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReadiumReaderWidget(publication: pub)),
        ),
      );

      await _waitWithPump(
        tester,
        () => locators.isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'No initial textLocator emitted',
      );
      final savedLocator = locators.last;

      await reader.goForward();
      await _waitWithPump(
        tester,
        () => locators.last != savedLocator,
        timeout: const Duration(seconds: 30),
        reason: 'goForward() did not produce a new locator',
      );
      final afterForward = locators.last;

      final ok = await reader.goToLocator(savedLocator);
      expect(ok, isTrue, reason: 'goToLocator should report success');

      await _waitWithPump(
        tester,
        () => locators.last != afterForward,
        timeout: const Duration(seconds: 30),
        reason: 'goToLocator() did not emit a new textLocator',
      );
      expect(
        locators.last.href,
        equals(savedLocator.href),
        reason: 'Restored locator should point to the saved resource',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('initialLocator restores the saved position on widget mount', (tester) async {
      final path = fixturePaths['moby_dick.epub'];
      expect(path, isNotNull, reason: 'Fixture moby_dick.epub missing from asset bundle');

      final pub = await reader.openPublication(path!);

      final locators = <Locator>[];
      final sub = reader.onTextLocatorChanged.listen(locators.add);
      addTearDown(sub.cancel);

      // First mount — advance past the first page so we have a non-default locator.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReadiumReaderWidget(publication: pub)),
        ),
      );
      await _waitWithPump(
        tester,
        () => locators.isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'No initial locator on first mount',
      );
      await reader.goForward();
      await _waitWithPump(
        tester,
        () => locators.length >= 2,
        timeout: const Duration(seconds: 15),
        reason: 'goForward() did not emit a second locator',
      );
      final savedLocator = locators.last;

      // Unmount, then remount with initialLocator.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));

      final preCount = locators.length;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadiumReaderWidget(publication: pub, initialLocator: savedLocator),
          ),
        ),
      );

      await _waitWithPump(
        tester,
        () => locators.length > preCount,
        timeout: const Duration(seconds: 30),
        reason: 'No textLocator emitted after remount with initialLocator',
      );

      expect(
        locators.last.href,
        equals(savedLocator.href),
        reason: 'Remounted widget should restore the saved resource',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('mounting the reader widget emits a ready reader status', (tester) async {
      final path = fixturePaths['moby_dick.epub'];
      expect(path, isNotNull, reason: 'Fixture moby_dick.epub missing from asset bundle');

      final pub = await reader.openPublication(path!);

      final statuses = <ReadiumReaderStatus>[];
      final sub = reader.onReaderStatusChanged.listen(statuses.add);
      addTearDown(sub.cancel);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReadiumReaderWidget(publication: pub)),
        ),
      );

      await _waitWithPump(
        tester,
        () => statuses.any((s) => s.isReady),
        timeout: const Duration(seconds: 30),
        reason: 'Reader never emitted a ready status',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('setEPUBPreferences applies without throwing', (tester) async {
      final path = fixturePaths['moby_dick.epub'];
      expect(path, isNotNull, reason: 'Fixture moby_dick.epub missing from asset bundle');

      final pub = await reader.openPublication(path!);

      final locators = <Locator>[];
      final sub = reader.onTextLocatorChanged.listen(locators.add);
      addTearDown(sub.cancel);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReadiumReaderWidget(publication: pub)),
        ),
      );
      await _waitWithPump(
        tester,
        () => locators.isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'No initial locator before applying preferences',
      );

      await expectLater(
        reader.setEPUBPreferences(EPUBPreferences(fontSize: 200)),
        completes,
        reason: 'setEPUBPreferences should not throw',
      );

      await tester.pumpWidget(const SizedBox());
    });
  });

  // ---------------------------------------------------------------------------
  // Audio playback control
  // ---------------------------------------------------------------------------

  group('Audio playback controls', () {
    test('audiobook pause then resume cycles through state transitions', () async {
      final path = fixturePaths['38533.audiobook'];
      expect(path, isNotNull, reason: 'Fixture 38533.audiobook missing from asset bundle');

      await reader.openPublication(path!);

      final states = <ReadiumTimebasedState>[];
      final sub = reader.onTimebasedPlayerStateChanged.listen(states.add);
      addTearDown(sub.cancel);

      await reader.audioEnable(prefs: AudioPreferences(speed: 1.0));
      await reader.play(null);

      await _waitUntil(
        () => states.any((s) => s.state == TimebasedState.playing),
        timeout: const Duration(seconds: 10),
        reason: 'Never reached initial playing state',
      );

      await reader.pause();
      await _waitUntil(
        () => states.last.state == TimebasedState.paused,
        timeout: const Duration(seconds: 10),
        reason: 'pause() did not produce a paused state',
      );

      await reader.resume();
      await _waitUntil(
        () => states.last.state == TimebasedState.playing,
        timeout: const Duration(seconds: 10),
        reason: 'resume() did not return to playing state',
      );

      await reader.pause();
    });

    test('audioSeekBy advances the timebased position', () async {
      final path = fixturePaths['38533.audiobook'];
      expect(path, isNotNull, reason: 'Fixture 38533.audiobook missing from asset bundle');

      await reader.openPublication(path!);

      final states = <ReadiumTimebasedState>[];
      final sub = reader.onTimebasedPlayerStateChanged.listen((state) {
        states.add(state);
        debugPrint('Player state changed: ${state.state}');
        debugPrint('- Locator: offset=${state.currentOffset},timestamp=${state.currentLocator?.locations?.timestamp}');
      });
      addTearDown(sub.cancel);

      await reader.audioEnable(prefs: AudioPreferences(speed: 1.0));
      await reader.play(null);

      await _waitUntil(
        () => states.any((s) => s.state == TimebasedState.playing && s.currentOffset != null),
        timeout: const Duration(seconds: 20),
        reason: 'Never reached playing state with an offset',
      );

      // Pause first so the offset comparison is not racing playback.
      await reader.pause();
      await _waitUntil(
        () => states.last.state == TimebasedState.paused,
        timeout: const Duration(seconds: 10),
        reason: 'Did not reach paused state',
      );
      final beforeSeek = states.last.currentOffset!;

      await reader.resume();
      await _waitUntil(
        () => states.last.state == TimebasedState.playing,
        timeout: const Duration(seconds: 10),
        reason: 'Did not resume playback',
      );

      await reader.audioSeekBy(const Duration(seconds: 10));

      await _waitUntil(
        () => states.last.currentOffset != null && states.last.currentOffset! > beforeSeek,
        timeout: const Duration(seconds: 5),
        reason: 'currentOffset did not advance after audioSeekBy(10s)',
      );

      expect(
        states.last.currentOffset! - beforeSeek,
        greaterThan(const Duration(seconds: 5)),
        reason: 'audioSeekBy(10s) should advance offset by at least ~5s',
      );
    });
  });
}

/// Drives the timebased playback path end-to-end:
///   enable -> play -> wait for [TimebasedState.playing] -> pause
///
/// Both pre-recorded audio (audiobook, media overlays) and TTS funnel through
/// the same timebased navigator on the native side, so the assertions are
/// identical — only the [enable] step differs.
Future<void> _exerciseAudioPlayback(
  FlutterReadium reader, {
  required Future<void> Function() enable,
  Duration timeout = const Duration(seconds: 20),
}) async {
  // Subscribe before play() so the early loading/playing transitions are
  // captured rather than racing the platform.
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

  // Stop audio output before the next test runs.
  await reader.pause();
}

/// Polls [predicate] every [pollInterval] until it returns true or [timeout]
/// elapses, in which case the surrounding test fails with [reason].
Future<void> _waitUntil(
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

/// Like [_waitUntil] but actively pumps Flutter frames while waiting.
///
/// Required when waiting on a platform view (UiKitView/AndroidView) to finish
/// rendering — Flutter only pumps frames when its own tree invalidates, so
/// async work happening inside a WKWebView (or analogous Android surface) can
/// stall until something forces a composite. Calling [WidgetTester.pump] on
/// every poll keeps that pipeline alive.
Future<void> _waitWithPump(
  WidgetTester tester,
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
    await tester.pump(pollInterval);
  }
}
