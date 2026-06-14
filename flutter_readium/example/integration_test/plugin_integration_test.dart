// Integration tests that open one fixture for each publication type
// (EPUB, WebPub with media overlays, audiobook) on the real native toolkit
// and verify the Dart side receives a well-formed [Publication].
//
// These tests exercise the Dart -> native -> Dart contract that pure Dart
// unit tests cannot reach. They run on iOS, Android, and Web via the example app.

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'test_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> fixturePaths;
  final reader = FlutterReadium();

  setUpAll(() async {
    fixturePaths = await loadFixturePaths();
  });

  // NOTE: Every testWidgets that mounts a ReadiumReaderWidget must end with
  // `await tester.pumpWidget(const SizedBox());` to unmount the platform view
  // before closePublication() runs in tearDown. Without this, the native
  // renderer may still be rendering while its resources are torn down.
  tearDown(() async {
    // closePublication stops audio/TTS and tears down the navigators, so a
    // previous publication's playback can't leak textLocators into the next test.
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

  test(
    'opens EPUB and enables TTS',
    // Web TTS uses the browser Web Speech API, which exposes no voices and is
    // blocked in automated/headless Chrome — real TTS playback can't be
    // exercised in the web test harness. Covered on iOS/Android.
    skip: kIsWeb ? 'Web Speech API unavailable in the web test harness' : false,
    () async {
      final path = fixturePaths['moby_dick.epub'];
      expect(path, isNotNull, reason: 'Fixture moby_dick.epub missing from asset bundle');

      await reader.openPublication(path!);

      await _exerciseAudioPlayback(
        reader,
        enable: () => reader.ttsEnable(TTSPreferences(speed: 1.0)),
        // First-time TTS engine init on Android can be slow.
        timeout: const Duration(seconds: 10),
      );
    },
  );

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
      diagnostics: () => 'readerStatus=$readerStatus, locators=${locators.length}',
    );
    await _waitForListStable(tester, locators);
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
    await _waitForListStable(tester, locators);
    expect(
      locators.last,
      isNot(equals(initialLocator)),
      reason: 'goForward() should emit a textLocator distinct from the initial one.',
    );

    await tester.pumpWidget(const SizedBox());
  });

  test('webpub with media-overlays opens (and plays audio on native)', () async {
    final path = fixturePaths['38533_overlay_preview.webpub'];
    expect(path, isNotNull, reason: 'Fixture 38533_overlay_preview.webpub missing from asset bundle');

    final pub = await reader.openPublication(path!);

    expect(pub.readingOrder, isNotEmpty);
    expect(pub.containsMediaOverlays, isTrue, reason: 'Overlay webpub should report media overlays');

    // Real audio playback isn't testable in the web harness (autoplay gating is
    // non-deterministic and the browser can't reliably decode the media), so on
    // web we assert open + media-overlay detection only. Native plays for real.
    if (!kIsWeb) {
      await _exerciseAudioPlayback(reader, enable: () => reader.audioEnable(prefs: AudioPreferences(speed: 1.0)));
    }
  });

  test('audiobook opens (and plays audio on native)', () async {
    final path = fixturePaths['38533.audiobook'];
    expect(path, isNotNull, reason: 'Fixture 38533.audiobook missing from asset bundle');

    final pub = await reader.openPublication(path!);

    expect(pub.readingOrder, isNotEmpty);
    expect(
      pub.conformsToReadiumAudiobook,
      isTrue,
      reason: 'Audiobook fixture should conform to the Readium audiobook profile',
    );

    // See note above: web asserts open + profile only; native plays for real.
    if (!kIsWeb) {
      await _exerciseAudioPlayback(reader, enable: () => reader.audioEnable(prefs: AudioPreferences(speed: 1.0)));
    }
  });

  // ---------------------------------------------------------------------------
  // Image tap API (getResourceBytes)
  // ---------------------------------------------------------------------------

  group(
    'EPUB image tap API',
    // The illustrated fixture is a native-bundled asset; the web integration
    // suite serves a different (webpub) fixture set, so this group runs on
    // iOS/Android only. getResourceBytes itself is implemented on web too.
    skip: kIsWeb ? 'Native-bundled fixture not available on web' : null,
    () {
      test('opens EPUB and reads publication metadata', () async {
        final path = fixturePaths[FixtureKeys.peterRabbitEpub];
        expect(
          path,
          isNotNull,
          reason: 'Fixture peter_rabbit.epub missing from asset bundle',
        );

        final pub = await reader.openPublication(path!);

        expect(pub.metadata.title, isNotEmpty);
        expect(pub.readingOrder, isNotEmpty);
      });

      test('getResourceBytes returns non-empty bytes for an image resource', () async {
        final path = fixturePaths[FixtureKeys.peterRabbitEpub];
        expect(path, isNotNull, reason: 'Fixture peter_rabbit.epub missing');

        final pub = await reader.openPublication(path!);

        // peter_rabbit.epub has many image resources (cover + interior plates).
        final imageLink = pub.resources.firstWhere(
          (l) =>
              l.type?.startsWith('image/') == true ||
              (l.href.contains('.png') || l.href.contains('.jpg') || l.href.contains('.jpeg')),
          orElse: () => throw StateError(
            'peter_rabbit.epub has no image resources — cannot test getResourceBytes',
          ),
        );

        final bytes = await reader.getResourceBytes(imageLink.href);
        expect(
          bytes,
          isNotEmpty,
          reason: 'getResourceBytes returned empty bytes for href: ${imageLink.href}',
        );
        // Sanity-check that the bytes look like an image by checking for known
        // magic bytes. JPEG starts with 0xFF 0xD8; PNG with 0x89 0x50 0x4E 0x47.
        final isJpeg = bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
        final isPng = bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
        expect(
          isJpeg || isPng,
          isTrue,
          reason:
              'Bytes for ${imageLink.href} do not start with a JPEG or PNG magic header '
              '(got 0x${bytes.take(4).map((b) => b.toRadixString(16).padLeft(2, "0")).join()})',
        );
      });
    },
  );

  // ---------------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------------

  group('PDF navigation and state', skip: kIsWeb ? 'PDF not supported on web' : null, () {
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

      ReadiumReaderStatus? readerStatus;
      final readerStatusSub = reader.onReaderStatusChanged.listen((status) => readerStatus = status);
      addTearDown(readerStatusSub.cancel);

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
        diagnostics: () => 'readerStatus=$readerStatus, locators=${locators.length}',
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

      ReadiumReaderStatus? readerStatus;
      final readerStatusSub = reader.onReaderStatusChanged.listen((status) => readerStatus = status);
      addTearDown(readerStatusSub.cancel);

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
        diagnostics: () => 'readerStatus=$readerStatus, locators=${locators.length}',
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
      skip: kIsWeb || _isAndroid()
          ? 'PDF text search not supported on Android (kotlin-toolkit has no PDF SearchService)'
          : false,
    );
  });

  // ---------------------------------------------------------------------------
  // Error path
  // ---------------------------------------------------------------------------

  test(
    'openPublication throws ReadiumException for an invalid path',
    skip: kIsWeb ? 'Error path differs on web (HTTP fetch vs file I/O)' : null,
    () async {
      await expectLater(reader.openPublication('/does-not-exist/no-such.epub'), throwsA(isA<ReadiumException>()));
    },
  );

  // ---------------------------------------------------------------------------
  // EPUB navigation & state
  // ---------------------------------------------------------------------------

  group('EPUB navigation and state', () {
    test(
      'searchInPublication returns hits for a common word in Moby-Dick',
      skip: kIsWeb ? 'searchInPublication not implemented on web (see docs/parity/web-search.md)' : false,
      () async {
        final path = fixturePaths['moby_dick.epub'];
        expect(path, isNotNull, reason: 'Fixture moby_dick.epub missing from asset bundle');

        await reader.openPublication(path!);

        final results = await reader.searchInPublication('whale');
        expect(results, isNotEmpty, reason: '"whale" should yield matches in Moby-Dick');
        expect(results.first.locator.href, isNotEmpty);
      },
    );

    testWidgets('goToLocator round-trips back to a saved position', (tester) async {
      final path = fixturePaths['moby_dick.epub'];
      expect(path, isNotNull, reason: 'Fixture moby_dick.epub missing from asset bundle');

      final pub = await reader.openPublication(path!);

      final locators = <Locator>[];
      final sub = reader.onTextLocatorChanged.listen(locators.add);
      addTearDown(sub.cancel);

      ReadiumReaderStatus? readerStatus;
      final readerStatusSub = reader.onReaderStatusChanged.listen((status) => readerStatus = status);
      addTearDown(readerStatusSub.cancel);

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
        diagnostics: () => 'readerStatus=$readerStatus, locators=${locators.length}',
      );
      await _waitForListStable(tester, locators);
      final savedLocator = locators.last;

      await reader.goForward();
      await _waitWithPump(
        tester,
        () => locators.last != savedLocator,
        timeout: const Duration(seconds: 30),
        reason: 'goForward() did not produce a new locator',
      );
      await _waitForListStable(tester, locators);
      final afterForward = locators.last;

      final ok = await reader.goToLocator(savedLocator);
      expect(ok, isTrue, reason: 'goToLocator should report success');

      await _waitWithPump(
        tester,
        () => locators.last != afterForward,
        timeout: const Duration(seconds: 30),
        reason: 'goToLocator() did not emit a new textLocator',
      );
      await _waitForListStable(tester, locators);
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
      await _waitForListStable(tester, locators);
      final initialLocator = locators.last;
      await reader.goForward();
      await _waitWithPump(
        tester,
        () => locators.last != initialLocator,
        timeout: const Duration(seconds: 15),
        reason: 'goForward() did not advance from the initial locator',
      );
      await _waitForListStable(tester, locators);
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
      await _waitForListStable(tester, locators);

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

    testWidgets('applyDecorations applies a highlight without throwing', (tester) async {
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
        reason: 'No initial locator before applying decorations',
      );

      // We can only assert that applying a decoration round-trips the bridge
      // without throwing. The visual result and onDecorationInteraction callback
      // live inside the navigator iframe and are not reachable by WidgetTester —
      // those are covered by unit tests / manual verification.
      await expectLater(
        reader.applyDecorations('test-highlights', [
          ReaderDecoration(
            id: 'd1',
            locator: locators.last,
            style: const ReaderDecorationStyle(style: DecorationStyle.highlight, tint: Colors.yellow),
          ),
        ]),
        completes,
        reason: 'applyDecorations should not throw',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('goToLocator round-trips cssSelector precision', (tester) async {
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
      await _waitForListStable(tester, locators);
      final savedLocator = locators.last;

      // goToLocator must preserve the full Locator (cssSelector / progression /
      // text) rather than collapsing to href-only. The initial locator does not
      // always carry a cssSelector (it can be progression-only), so we assert the
      // cssSelector round-trip opportunistically, only when one is present.
      final savedCssSelector = savedLocator.locations?.cssSelector;

      await reader.goForward();
      await _waitWithPump(
        tester,
        () => locators.last != savedLocator,
        timeout: const Duration(seconds: 30),
        reason: 'goForward() did not produce a new locator',
      );

      final ok = await reader.goToLocator(savedLocator);
      expect(ok, isTrue, reason: 'goToLocator should report success');
      await _waitWithPump(
        tester,
        () => locators.last.href == savedLocator.href,
        timeout: const Duration(seconds: 30),
        reason: 'goToLocator() did not return to the saved resource',
      );
      expect(locators.last.href, equals(savedLocator.href));

      if (savedCssSelector != null) {
        expect(
          locators.last.locations?.cssSelector,
          equals(savedCssSelector),
          reason: 'Restored locator should round-trip the saved cssSelector precisely',
        );
      }

      await tester.pumpWidget(const SizedBox());
    });
  });

  // ---------------------------------------------------------------------------
  // Audio playback control
  // ---------------------------------------------------------------------------

  group(
    'Audio playback controls',
    skip: kIsWeb ? 'Real audio playback is not available in the web test harness' : null,
    () {
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
          timeout: const Duration(seconds: 10),
          reason: 'currentOffset did not advance after audioSeekBy($seekDuration)',
        );

        expect(
          states.last.currentOffset! - beforeSeek,
          greaterThanOrEqualTo(seekDuration - tolerance),
          reason: 'audioSeekBy() should have advanced offset by ~seekDuration',
        );
      });
    },
  );

  // ---------------------------------------------------------------------------
  // Web feature parity
  //
  // These exercise reading/playback modes and web-only behaviours whose fixtures
  // are served locally from example/web/ (see test_fixtures_web.dart). They are
  // web-gated: the local exploded webpub fixtures are not wired into the native
  // asset loader. Extending them to native (the equivalent .webpub assets are
  // bundled) is a follow-up via a key->basename alias in test_fixtures_native.
  // ---------------------------------------------------------------------------

  group('Web feature parity', skip: kIsWeb ? null : 'Web-only fixtures / behaviour', () {
    testWidgets('fixed-layout EPUB opens and navigates', (tester) async {
      final path = fixturePaths[FixtureKeys.fixedLayout];
      expect(path, isNotNull, reason: 'Fixture ${FixtureKeys.fixedLayout} missing');

      final pub = await reader.openPublication(path!);

      expect(pub.readingOrder, isNotEmpty);
      expect(
        pub.metadata.presentation.layout,
        equals(EpubLayout.fixed),
        reason: 'Fixed-layout fixture should report a fixed presentation layout',
      );

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
        reason: 'Fixed-layout reader never emitted an initial textLocator',
      );
      final initialLocator = locators.last;

      await reader.goForward();
      await _waitWithPump(
        tester,
        () => locators.last != initialLocator,
        timeout: const Duration(seconds: 15),
        reason: 'goForward() did not produce a new textLocator in fixed-layout EPUB',
      );

      await tester.pumpWidget(const SizedBox());
    });

    // NOTE: these assert open + render only, not real audio playback. Audio
    // playback isn't reliably testable in the web harness (autoplay gating is
    // non-deterministic and the browser can't reliably decode the media), so
    // we verify the publication opens, reports the right profile, and renders.
    testWidgets('guided-navigation publication opens and renders', (tester) async {
      final path = fixturePaths[FixtureKeys.guidedNav];
      expect(path, isNotNull, reason: 'Fixture ${FixtureKeys.guidedNav} missing');

      final pub = await reader.openPublication(path!);
      expect(pub.readingOrder, isNotEmpty);

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
        reason: 'Guided-navigation reader never emitted an initial textLocator',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('comic media-overlay EPUB opens, reports overlays, and renders', (tester) async {
      final path = fixturePaths[FixtureKeys.comic];
      expect(path, isNotNull, reason: 'Fixture ${FixtureKeys.comic} missing');

      final pub = await reader.openPublication(path!);

      expect(pub.readingOrder, isNotEmpty);
      expect(
        pub.containsMediaOverlays,
        isTrue,
        reason: 'Comic fixture should report media overlays',
      );

      // Panel pan/zoom and audio happen inside the navigator iframe / browser
      // media layer and aren't observable in the harness — assert open +
      // media-overlay detection + that the reader renders.
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
        reason: 'Comic reader never emitted an initial textLocator',
      );

      await tester.pumpWidget(const SizedBox());
    });

    test('onErrorEvent emits when opening an unreachable publication', () async {
      final errors = <ReadiumError>[];
      final sub = reader.onErrorEvent.listen(errors.add);
      addTearDown(sub.cancel);

      // openPublication for a 404 manifest rejects on web; the JS catch path also
      // forwards the failure to the onErrorEvent broadcast stream
      // (see docs/parity/web-error-event.md). We only care that the stream is
      // subscribable without UnimplementedError and that it emits.
      try {
        await reader.openPublication('/no-such-fixture/manifest.json');
      } on Object {
        // Expected — the open fails; the error event is what we assert on.
      }

      await _waitUntil(
        () => errors.isNotEmpty,
        timeout: const Duration(seconds: 15),
        reason: 'onErrorEvent did not emit after a failed openPublication',
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
///
/// On timeout the failure message includes how long we actually waited plus,
/// when supplied, the result of [diagnostics] — a closure that captures live
/// state (e.g. the latest reader status, how many events have arrived). This is
/// what distinguishes a genuinely slow webview from one that stalled and never
/// emitted: "waited 30000ms | readerStatus=loading, events=0" reads very
/// differently from "readerStatus=ready, events=0". The string is both embedded
/// in the [fail] reason (shown in the CI error group) and `debugPrint`ed
/// (timestamped in the test-runner stream).
Future<void> _waitWithPump(
  WidgetTester tester,
  bool Function() predicate, {
  required Duration timeout,
  String? reason,
  String Function()? diagnostics,
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final start = DateTime.now();
  final deadline = start.add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      final elapsedMs = DateTime.now().difference(start).inMilliseconds;
      final diag = diagnostics != null ? ' | ${diagnostics()}' : '';
      final base = reason ?? 'Condition did not become true within $timeout';
      debugPrint('⏱️ _waitWithPump TIMEOUT after ${elapsedMs}ms: $base$diag');
      fail('$base (waited ${elapsedMs}ms)$diag');
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

/// Returns true on Android. Uses [defaultTargetPlatform] which is safe on all
/// platforms (unlike `dart:io` Platform which is unavailable on web).
bool _isAndroid() => defaultTargetPlatform == TargetPlatform.android;
