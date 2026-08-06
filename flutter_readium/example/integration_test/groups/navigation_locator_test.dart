import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import '../readium_integration_harness.dart';
import '../test_suite_setup.dart';
import '../test_fixtures.dart';

void main() {
  final harness = suiteHarness();

  group('Navigation and locator round-tripping', () {
    testWidgets('EPUB goForward emits a new textLocator', (tester) async {
      final path = harness.fixturePath(
        FixtureKeys.reflowableEpub,
        reason: 'Fixture ${FixtureKeys.reflowableEpub} missing from asset bundle',
      );
      final pub = await harness.readium.openPublication(path);

      final locators = <Locator>[];
      ReadiumReaderStatus? readerStatus;
      final readerStatusSub = harness.readium.onReaderStatusChanged.listen((status) => readerStatus = status);
      final textLocatorSub = harness.readium.onTextLocatorChanged.listen(locators.add);
      addTearDown(textLocatorSub.cancel);
      addTearDown(readerStatusSub.cancel);

      await tester.pumpWidget(bareReaderApp(pub));

      await waitWithPump(
        tester,
        () => locators.isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'ReadiumReaderWidget never emitted an initial textLocator',
        diagnostics: () => 'readerStatus=$readerStatus, locators=${locators.length}',
      );
      await waitForListStable(tester, locators);
      final initialLocator = locators.last;

      expect(
        readerStatus,
        equals(ReadiumReaderStatus.ready),
        reason: 'Reader should be in ready status after widget has mounted',
      );

      await harness.readium.goForward();

      await waitWithPump(
        tester,
        () => locators.last != initialLocator,
        timeout: const Duration(seconds: 15),
        reason: 'goForward() did not produce a new textLocator',
      );
      await waitForListStable(tester, locators);
      expect(
        locators.last,
        isNot(equals(initialLocator)),
        reason: 'goForward() should emit a textLocator distinct from the initial one.',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('EPUB goToLocator round-trips back to a saved position', (tester) async {
      final path = harness.fixturePath(
        FixtureKeys.reflowableEpub,
        reason: 'Fixture ${FixtureKeys.reflowableEpub} missing from asset bundle',
      );
      final pub = await harness.readium.openPublication(path);

      final locators = <Locator>[];
      final sub = harness.readium.onTextLocatorChanged.listen(locators.add);
      addTearDown(sub.cancel);

      ReadiumReaderStatus? readerStatus;
      final readerStatusSub = harness.readium.onReaderStatusChanged.listen((status) => readerStatus = status);
      addTearDown(readerStatusSub.cancel);

      await tester.pumpWidget(bareReaderApp(pub));

      await waitWithPump(
        tester,
        () => locators.isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'No initial textLocator emitted',
        diagnostics: () => 'readerStatus=$readerStatus, locators=${locators.length}',
      );
      await waitForListStable(tester, locators);
      final savedLocator = locators.last;

      await harness.readium.goForward();
      await waitWithPump(
        tester,
        () => locators.last != savedLocator,
        timeout: const Duration(seconds: 30),
        reason: 'goForward() did not produce a new locator',
      );
      await waitForListStable(tester, locators);
      final afterForward = locators.last;

      final ok = await harness.readium.goToLocator(savedLocator);
      expect(ok, isTrue, reason: 'goToLocator should report success');

      await waitWithPump(
        tester,
        () => locators.last != afterForward,
        timeout: const Duration(seconds: 30),
        reason: 'goToLocator() did not emit a new textLocator',
      );
      await waitForListStable(tester, locators);
      expect(
        locators.last.href,
        equals(savedLocator.href),
        reason: 'Restored locator should point to the saved resource',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('EPUB goToLocator round-trips cssSelector precision', (tester) async {
      final path = harness.fixturePath(
        FixtureKeys.reflowableEpub,
        reason: 'Fixture ${FixtureKeys.reflowableEpub} missing from asset bundle',
      );
      final pub = await harness.readium.openPublication(path);

      final locators = <Locator>[];
      final sub = harness.readium.onTextLocatorChanged.listen(locators.add);
      addTearDown(sub.cancel);

      await tester.pumpWidget(bareReaderApp(pub));
      await waitWithPump(
        tester,
        () => locators.isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'No initial textLocator emitted',
      );
      await waitForListStable(tester, locators);
      final savedLocator = locators.last;
      final savedCssSelector = savedLocator.locations?.cssSelector;

      await harness.readium.goForward();
      await waitWithPump(
        tester,
        () => locators.last != savedLocator,
        timeout: const Duration(seconds: 30),
        reason: 'goForward() did not produce a new locator',
      );

      final locatorCount = locators.length;
      final ok = await harness.readium.goToLocator(savedLocator);
      expect(ok, isTrue, reason: 'goToLocator should report success');
      await waitWithPump(
        tester,
        () => locators.length > locatorCount && locators.last.href == savedLocator.href,
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

    testWidgets('DiViNa goForward/goBackward changes and restores locator', (tester) async {
      final fixtureKey = kIsWeb ? FixtureKeys.divina : FixtureKeys.divinaComicCbz;
      final path = harness.fixturePath(
        fixtureKey,
        reason: 'Fixture $fixtureKey missing from asset bundle',
      );
      final pub = await harness.readium.openPublication(path);

      final locators = <Locator>[];
      final sub = harness.readium.onTextLocatorChanged.listen(locators.add);
      addTearDown(sub.cancel);

      ReadiumReaderStatus? readerStatus;
      final readerStatusSub = harness.readium.onReaderStatusChanged.listen((status) => readerStatus = status);
      addTearDown(readerStatusSub.cancel);

      await tester.pumpWidget(bareReaderApp(pub));

      await waitWithPump(
        tester,
        () => locators.isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'DiViNa reader never emitted an initial textLocator',
        diagnostics: () => 'readerStatus=$readerStatus, locators=${locators.length}',
      );
      await waitForListStable(tester, locators);
      final initialLocator = locators.last;

      await harness.readium.goForward();
      await waitWithPump(
        tester,
        () => locators.last != initialLocator,
        timeout: const Duration(seconds: 15),
        reason: 'goForward() did not produce a new DiViNa locator',
      );
      await waitForListStable(tester, locators);
      final afterForward = locators.last;

      expect(
        afterForward.href,
        isNot(equals(initialLocator.href)),
        reason: 'goForward() should move away from the initial DiViNa resource',
      );

      await harness.readium.goBackward();
      await waitWithPump(
        tester,
        () => locators.last != afterForward,
        timeout: const Duration(seconds: 15),
        reason: 'goBackward() did not produce a new DiViNa locator',
      );
      await waitForListStable(tester, locators);

      expect(
        locators.last.href,
        equals(initialLocator.href),
        reason: 'goBackward() should return to the initial DiViNa resource',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'paginated PDF goForward/goBackward step exactly one page',
      (tester) async {
        final path = harness.fixturePath(
          FixtureKeys.timeMachinePdf,
          reason: 'Fixture ${FixtureKeys.timeMachinePdf} missing from asset bundle',
        );
        final pub = await harness.readium.openPublication(path);

        final locators = <Locator>[];
        final sub = harness.readium.onTextLocatorChanged.listen(locators.add);
        addTearDown(sub.cancel);

        ReadiumReaderStatus? readerStatus;
        final readerStatusSub = harness.readium.onReaderStatusChanged.listen((status) => readerStatus = status);
        addTearDown(readerStatusSub.cancel);

        await tester.pumpWidget(bareReaderApp(pub));

        await waitWithPump(
          tester,
          () => locators.isNotEmpty,
          timeout: const Duration(seconds: 30),
          reason: 'No initial textLocator emitted',
          diagnostics: () => 'readerStatus=$readerStatus, locators=${locators.length}',
        );

        await harness.readium.setPDFPreferences(const PDFPreferences(layout: PDFLayout.paginated));
        await waitForListStable(tester, locators);
        final startPage = locators.last.locations!.position!;

        await harness.readium.goForward();
        await waitWithPump(
          tester,
          () => locators.last.locations?.position == startPage + 1,
          timeout: const Duration(seconds: 15),
          reason: 'goForward() did not settle on startPage + 1 (start=$startPage)',
        );
        expect(locators.last.locations?.position, equals(startPage + 1));

        final afterForward = locators.last.locations!.position!;
        await harness.readium.goBackward();
        await waitWithPump(
          tester,
          () => locators.last.locations?.position == afterForward - 1,
          timeout: const Duration(seconds: 15),
          reason: 'goBackward() did not return to afterForward - 1 (afterForward=$afterForward)',
        );
        expect(locators.last.locations?.position, equals(afterForward - 1));

        await tester.pumpWidget(const SizedBox());
      },
      skip: kIsWeb,
    );

    testWidgets(
      'vertical-scroll PDF goForward/goBackward advances and retreats page position',
      (tester) async {
        final path = harness.fixturePath(
          FixtureKeys.timeMachinePdf,
          reason: 'Fixture ${FixtureKeys.timeMachinePdf} missing from asset bundle',
        );
        final pub = await harness.readium.openPublication(path);

        final locators = <Locator>[];
        final sub = harness.readium.onTextLocatorChanged.listen(locators.add);
        addTearDown(sub.cancel);

        ReadiumReaderStatus? readerStatus;
        final readerStatusSub = harness.readium.onReaderStatusChanged.listen((status) => readerStatus = status);
        addTearDown(readerStatusSub.cancel);

        await tester.pumpWidget(bareReaderApp(pub));

        await waitWithPump(
          tester,
          () => locators.isNotEmpty,
          timeout: const Duration(seconds: 30),
          reason: 'No initial textLocator emitted',
          diagnostics: () => 'readerStatus=$readerStatus, locators=${locators.length}',
        );

        await harness.readium.setPDFPreferences(const PDFPreferences(layout: PDFLayout.scrollVertical));
        await waitForListStable(tester, locators);
        final startPage = locators.last.locations!.position!;

        await harness.readium.goForward();
        await waitWithPump(
          tester,
          () => (locators.last.locations?.position ?? startPage) > startPage,
          timeout: const Duration(seconds: 15),
          reason: 'goForward() did not advance past the start page (start=$startPage)',
        );
        final advanced = locators.last.locations!.position!;
        expect(advanced, greaterThan(startPage));

        await harness.readium.goBackward();
        await waitWithPump(
          tester,
          () => (locators.last.locations?.position ?? advanced) < advanced,
          timeout: const Duration(seconds: 15),
          reason: 'goBackward() did not retreat past the advanced page (advanced=$advanced)',
        );
        expect(locators.last.locations!.position, lessThan(advanced));

        await tester.pumpWidget(const SizedBox());
      },
      skip: kIsWeb,
    );

    testWidgets(
      'PDF goToLocator round-trips back to a saved page',
      (tester) async {
        final path = harness.fixturePath(
          FixtureKeys.timeMachinePdf,
          reason: 'Fixture ${FixtureKeys.timeMachinePdf} missing from asset bundle',
        );
        final pub = await harness.readium.openPublication(path);

        final locators = <Locator>[];
        final sub = harness.readium.onTextLocatorChanged.listen(locators.add);
        addTearDown(sub.cancel);

        await tester.pumpWidget(bareReaderApp(pub));

        await waitWithPump(
          tester,
          () => locators.isNotEmpty,
          timeout: const Duration(seconds: 30),
          reason: 'No initial locator emitted',
        );
        await waitForListStable(tester, locators);

        final baselinePage = locators.last.locations!.position!;
        await harness.readium.goForward();
        await waitWithPump(
          tester,
          () => locators.last.locations?.position != baselinePage,
          timeout: const Duration(seconds: 15),
          reason: 'goForward() did not produce a new locator (baseline=$baselinePage)',
        );
        await waitForListStable(tester, locators);
        final savedLocator = locators.last;
        final savedPage = savedLocator.locations!.position!;

        await harness.readium.goForward();
        await waitWithPump(
          tester,
          () => locators.last.locations?.position != savedPage,
          timeout: const Duration(seconds: 15),
          reason: 'second goForward() did not produce a new locator (saved=$savedPage)',
        );
        await waitForListStable(tester, locators);
        final afterSecondForward = locators.last;

        final ok = await harness.readium.goToLocator(savedLocator);
        expect(ok, isTrue, reason: 'goToLocator should report success');

        await waitWithPump(
          tester,
          () => locators.last.locations?.position == savedPage,
          timeout: const Duration(seconds: 15),
          reason: 'goToLocator() did not settle on the saved page (saved=$savedPage, lastBefore=$afterSecondForward)',
        );

        expect(
          locators.last.locations?.position,
          equals(savedPage),
          reason: 'Restored locator should be on the saved page',
        );

        await tester.pumpWidget(const SizedBox());
      },
      skip: kIsWeb,
    );

    testWidgets(
      'fixed-layout EPUB opens and navigates',
      (tester) async {
        final path = harness.fixturePath(
          FixtureKeys.fixedLayout,
          reason: 'Fixture ${FixtureKeys.fixedLayout} missing',
        );
        final pub = await harness.readium.openPublication(path);

        expect(pub.readingOrder, isNotEmpty);
        expect(
          pub.metadata.presentation.layout,
          equals(EpubLayout.fixed),
          reason: 'Fixed-layout fixture should report a fixed presentation layout',
        );

        final locators = <Locator>[];
        final sub = harness.readium.onTextLocatorChanged.listen(locators.add);
        addTearDown(sub.cancel);

        await tester.pumpWidget(bareReaderApp(pub));
        await waitWithPump(
          tester,
          () => locators.isNotEmpty,
          timeout: const Duration(seconds: 30),
          reason: 'Fixed-layout reader never emitted an initial textLocator',
        );
        await waitForListStable(tester, locators);
        final initialLocator = locators.last;

        await harness.readium.goForward();
        await waitWithPump(
          tester,
          () => locators.last != initialLocator,
          timeout: const Duration(seconds: 15),
          reason: 'goForward() did not produce a new textLocator in fixed-layout EPUB',
        );
        await waitForListStable(tester, locators);
        final afterForward = locators.last;

        expect(
          afterForward,
          isNot(equals(initialLocator)),
          reason: 'goForward() should move away from the initial fixed-layout locator',
        );

        await harness.readium.goBackward();
        await waitWithPump(
          tester,
          () => locators.last != afterForward,
          timeout: const Duration(seconds: 15),
          reason: 'goBackward() did not produce a new textLocator in fixed-layout EPUB',
        );
        await waitForListStable(tester, locators);

        expect(
          locators.last.href,
          equals(initialLocator.href),
          reason: 'goBackward() should return to the initial fixed-layout resource',
        );

        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
