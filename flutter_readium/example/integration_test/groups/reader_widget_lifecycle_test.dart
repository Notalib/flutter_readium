import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import '../readium_integration_harness.dart';
import '../test_suite_setup.dart';
import '../test_fixtures.dart';

void main() {
  final harness = suiteHarness();

  group('Reader widget lifecycle', () {
    testWidgets('mounting EPUB reader emits a ready reader status', (tester) async {
      final path = harness.fixturePath(
        FixtureKeys.reflowableEpub,
        reason: 'Fixture ${FixtureKeys.reflowableEpub} missing from asset bundle',
      );
      final pub = await harness.readium.openPublication(path);

      final statuses = <ReadiumReaderStatus>[];
      final sub = harness.readium.onReaderStatusChanged.listen(statuses.add);
      addTearDown(sub.cancel);

      await tester.pumpWidget(bareReaderApp(pub));

      await waitWithPump(
        tester,
        () => statuses.any((s) => s.isReady),
        timeout: const Duration(seconds: 30),
        reason: 'Reader never emitted a ready status',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'mounting PDF reader emits initial textLocator with page position',
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
          reason: 'PDF ReadiumReaderWidget never emitted an initial textLocator',
        );

        expect(
          locators.first.locations?.position,
          isNotNull,
          reason: 'PDF locator should carry a 1-based page position',
        );
        expect(locators.first.locations?.position, equals(1), reason: 'Initial PDF locator should be on page 1');

        await tester.pumpWidget(const SizedBox());
      },
      skip: kIsWeb,
    );

    testWidgets('initialLocator restores the saved EPUB position on widget mount', (tester) async {
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
        reason: 'No initial locator on first mount',
      );
      await waitForListStable(tester, locators);
      final initialLocator = locators.last;

      await harness.readium.goForward();
      await waitWithPump(
        tester,
        () => locators.last != initialLocator,
        timeout: const Duration(seconds: 15),
        reason: 'goForward() did not advance from the initial locator',
      );
      await waitForListStable(tester, locators);
      final savedLocator = locators.last;

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));

      final preCount = locators.length;
      await tester.pumpWidget(bareReaderApp(pub, initialLocator: savedLocator));

      await waitWithPump(
        tester,
        () => locators.length > preCount,
        timeout: const Duration(seconds: 30),
        reason: 'No textLocator emitted after remount with initialLocator',
      );
      await waitForListStable(tester, locators);

      expect(
        locators.last.href,
        equals(savedLocator.href),
        reason: 'Remounted widget should restore the saved resource',
      );

      await tester.pumpWidget(const SizedBox());
    });

    group('fully-wired smoke tests', () {
      testWidgets('EPUB', (tester) async {
        final path = harness.fixturePath(
          FixtureKeys.reflowableEpub,
          reason: 'Fixture ${FixtureKeys.reflowableEpub} missing from asset bundle',
        );

        final pub = await harness.readium.openPublication(path);
        await mountFullyWiredAndSmokeTest(
          harness,
          tester,
          pub,
          reason: 'Fully-wired EPUB reader never emitted an initial textLocator',
        );
      });

      testWidgets(
        'PDF',
        (tester) async {
          final path = harness.fixturePath(
            FixtureKeys.timeMachinePdf,
            reason: 'Fixture ${FixtureKeys.timeMachinePdf} missing from asset bundle',
          );

          final pub = await harness.readium.openPublication(path);
          await mountFullyWiredAndSmokeTest(
            harness,
            tester,
            pub,
            reason: 'Fully-wired PDF reader never emitted an initial textLocator',
          );
        },
        skip: kIsWeb,
      );

      testWidgets('WebPub with media overlay', (tester) async {
        final path = harness.fixturePath(
          FixtureKeys.overlayWebpub,
          reason: 'Fixture ${FixtureKeys.overlayWebpub} missing from asset bundle',
        );

        final pub = await harness.readium.openPublication(path);
        await mountFullyWiredAndSmokeTest(
          harness,
          tester,
          pub,
          reason: 'Fully-wired media-overlay reader never emitted an initial textLocator',
        );
      });

      testWidgets(
        'DiViNa comic',
        (tester) async {
          final fixtureKey = kIsWeb ? FixtureKeys.divina : FixtureKeys.divinaComicCbz;
          final path = harness.fixturePath(
            fixtureKey,
            reason: 'Fixture $fixtureKey missing from asset bundle',
          );

          final pub = await harness.readium.openPublication(path);
          expect(
            pub.conformsToReadiumDivina,
            isTrue,
            reason: 'DiViNa fixture should conform to the Readium DiViNa profile',
          );
          await mountFullyWiredAndSmokeTest(
            harness,
            tester,
            pub,
            reason: 'Fully-wired DiViNa reader never emitted an initial textLocator',
          );
        },
      );
    });
  });
}
