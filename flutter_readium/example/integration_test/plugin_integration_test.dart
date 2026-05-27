// Integration tests that open one fixture for each publication type
// (EPUB, WebPub with media overlays, audiobook) on the real native toolkit
// and verify the Dart side receives a well-formed [Publication].
//
// These tests exercise the Dart -> native -> Dart contract that pure Dart
// unit tests cannot reach. They run on iOS and Android via the example app.

import 'dart:io';

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

  // NOTE: Every testWidgets that mounts a ReadiumReaderWidget must end with
  // `await tester.pumpWidget(const SizedBox());` to unmount the platform view
  // before closePublication() runs in tearDown. Without this, the native
  // renderer may still be rendering while its resources are torn down.
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
  // PDF
  // ---------------------------------------------------------------------------

  group('PDF navigation and state', () {
    test('opens PDF successfully', () async {
      final path = fixturePaths['pdf_test.pdf'];
      expect(path, isNotNull, reason: 'Fixture pdf_test.pdf missing from asset bundle');

      final pub = await reader.openPublication(path!);

      expect(pub.metadata.title, isNotEmpty);
      expect(pub.readingOrder, isNotEmpty);
      expect(pub.conformsToReadiumPDF, isTrue, reason: 'PDF fixture should conform to the Readium PDF profile');
    });

    testWidgets('setPDFPreferences applies without throwing', (tester) async {
      final path = fixturePaths['time_machine.pdf'];
      expect(path, isNotNull, reason: 'Fixture time_machine.pdf missing from asset bundle');

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
        reason: 'No initial locator before applying PDF preferences',
      );

      await expectLater(
        reader.setPDFPreferences(const PDFPreferences(layout: PDFLayout.scrollVertical)),
        completes,
        reason: 'setPDFPreferences should not throw',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('mounting PDF reader widget emits initial textLocator with page position', (tester) async {
      final path = fixturePaths['time_machine.pdf'];
      expect(path, isNotNull, reason: 'Fixture time_machine.pdf missing from asset bundle');

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
        reason: 'PDF ReadiumReaderWidget never emitted an initial textLocator',
      );

      expect(locators.first.locations?.position, isNotNull, reason: 'PDF locator should carry a 1-based page position');
      expect(locators.first.locations?.position, equals(1), reason: 'Initial PDF locator should be on page 1');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('goForward()/goBackward() in paginated PDF step exactly one page', (tester) async {
      final path = fixturePaths['time_machine.pdf'];
      expect(path, isNotNull, reason: 'Fixture time_machine.pdf missing from asset bundle');

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

      // Paginated layout: iOS uses PDFKit's snap-to-page mode; Android maps
      // it to Pdfium's HORIZONTAL scroll axis (single-page-wide viewport).
      // Both yield one page per goForward/goBackward.
      await reader.setPDFPreferences(const PDFPreferences(layout: PDFLayout.paginated));
      // The navigator can emit settling locators after initial layout and again
      // after the preference change. Wait for the emission stream to quiesce
      // before snapshotting our baseline page.
      await _waitForListStable(tester, locators);
      final startPage = locators.last.locations!.position!;

      await reader.goForward();
      await _waitWithPump(
        tester,
        () => locators.last.locations?.position == startPage + 1,
        timeout: const Duration(seconds: 15),
        reason: 'goForward() did not settle on startPage + 1 (start=$startPage)',
      );
      expect(locators.last.locations?.position, equals(startPage + 1));

      final afterForward = locators.last.locations!.position!;
      await reader.goBackward();
      await _waitWithPump(
        tester,
        () => locators.last.locations?.position == afterForward - 1,
        timeout: const Duration(seconds: 15),
        reason: 'goBackward() did not return to afterForward - 1 (afterForward=$afterForward)',
      );
      expect(locators.last.locations?.position, equals(afterForward - 1));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('goForward()/goBackward() in vertical-scroll PDF advances/retreats the page position', (tester) async {
      final path = fixturePaths['time_machine.pdf'];
      expect(path, isNotNull, reason: 'Fixture time_machine.pdf missing from asset bundle');

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

      // Vertical scroll: viewport scrolls by its own height, which can cover
      // multiple pages depending on the PDF's aspect ratio — only assert
      // direction, not strict +/-1.
      await reader.setPDFPreferences(const PDFPreferences(layout: PDFLayout.scrollVertical));
      await _waitForListStable(tester, locators);
      final startPage = locators.last.locations!.position!;

      await reader.goForward();
      await _waitWithPump(
        tester,
        () => (locators.last.locations?.position ?? startPage) > startPage,
        timeout: const Duration(seconds: 15),
        reason: 'goForward() did not advance past the start page (start=$startPage)',
      );
      final advanced = locators.last.locations!.position!;
      expect(advanced, greaterThan(startPage));

      await reader.goBackward();
      await _waitWithPump(
        tester,
        () => (locators.last.locations?.position ?? advanced) < advanced,
        timeout: const Duration(seconds: 15),
        reason: 'goBackward() did not retreat past the advanced page (advanced=$advanced)',
      );
      expect(locators.last.locations!.position, lessThan(advanced));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('goToLocator round-trips back to a saved PDF page', (tester) async {
      final path = fixturePaths['time_machine.pdf'];
      expect(path, isNotNull, reason: 'Fixture time_machine.pdf missing from asset bundle');

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
        reason: 'No initial locator emitted',
      );
      // Wait for initial layout to settle before snapshotting; on Android the
      // Pdfium fragment can emit a follow-up locator at a different page after
      // initial render, and we want the saved locator to reflect a stable
      // position so the round-trip assertion isn't racing that settling.
      await _waitForListStable(tester, locators);

      // Advance once to leave a known baseline page we can return to.
      final baselinePage = locators.last.locations!.position!;
      await reader.goForward();
      await _waitWithPump(
        tester,
        () => locators.last.locations?.position != baselinePage,
        timeout: const Duration(seconds: 15),
        reason: 'goForward() did not produce a new locator (baseline=$baselinePage)',
      );
      await _waitForListStable(tester, locators);
      final savedLocator = locators.last;
      final savedPage = savedLocator.locations!.position!;

      // Advance again so goToLocator has somewhere to come back from.
      await reader.goForward();
      await _waitWithPump(
        tester,
        () => locators.last.locations?.position != savedPage,
        timeout: const Duration(seconds: 15),
        reason: 'second goForward() did not produce a new locator (saved=$savedPage)',
      );
      await _waitForListStable(tester, locators);
      final afterSecondForward = locators.last;

      final ok = await reader.goToLocator(savedLocator);
      expect(ok, isTrue, reason: 'goToLocator should report success');

      await _waitWithPump(
        tester,
        () => locators.last.locations?.position == savedPage,
        timeout: const Duration(seconds: 15),
        reason:
            'goToLocator() did not settle on the saved page '
            '(saved=$savedPage, lastBefore=$afterSecondForward)',
      );

      expect(
        locators.last.locations?.position,
        equals(savedPage),
        reason: 'Restored locator should be on the saved page',
      );

      await tester.pumpWidget(const SizedBox());
    });

    test(
      'searchInPublication returns hits for a common word in a text PDF',
      () async {
        final path = fixturePaths['time_machine.pdf'];
        expect(path, isNotNull, reason: 'Fixture time_machine.pdf missing from asset bundle');

        await reader.openPublication(path!);

        final results = await reader.searchInPublication('time');
        expect(results, isNotEmpty, reason: '"time" should yield matches in The Time Machine PDF');
        expect(results.first.locator.href, isNotEmpty);
        expect(
          results.first.locator.locations?.position,
          isNotNull,
          reason: 'PDF search hit should carry a 1-based page position',
        );
      },
      skip: Platform.isAndroid
          ? 'PDF text search not supported on Android (kotlin-toolkit has no PDF SearchService)'
          : false,
    );
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
      final sub = reader.onTimebasedPlayerStateChanged.listen(states.add);
      addTearDown(sub.cancel);

      await reader.audioEnable(prefs: AudioPreferences(speed: 1.0));
      await reader.play(null);

      await _waitUntil(
        () => states.any((s) => s.state == TimebasedState.playing && s.currentOffset != null),
        timeout: const Duration(seconds: 20),
        reason: 'Never reached playing state with an offset',
      );

      final beforeSeek = states.last.currentOffset!;
      // Keep the seek small enough to stay within the current audiobook track.
      // AudioNavigator.seek(offset) is ignored if offset goes beyond end of current resource.
      final seekDuration = const Duration(seconds: 5);
      final tolerance = const Duration(milliseconds: 500);
      final expectedMinOffset = beforeSeek + seekDuration - tolerance;

      await reader.audioSeekBy(seekDuration);
      await reader.resume();

      await _waitUntil(
        () => states.last.currentOffset != null && states.last.currentOffset! >= expectedMinOffset,
        timeout: const Duration(seconds: 110),
        reason: 'currentOffset did not advance after audioSeekBy($seekDuration)',
      );

      expect(
        states.last.currentOffset! - beforeSeek,
        greaterThanOrEqualTo(seekDuration - tolerance),
        reason: 'audioSeekBy() should have advanced offset by ~seekDuration',
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

/// Pumps frames until [list]'s length has not changed for [stableFor]. Useful
/// for letting a navigator's currentLocator StateFlow settle before snapshotting
/// a baseline position. Times out after [timeout] and returns regardless.
Future<void> _waitForListStable<T>(
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
