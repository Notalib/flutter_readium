import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/readium_integration_harness.dart';
import '../test_fixtures.dart';

void definePreferencesDecorationsResourcesTests(ReadiumIntegrationHarness harness) {
  group('Preferences, decorations, and resource APIs', () {
    testWidgets('setEPUBPreferences applies and reader continues emitting locators', (tester) async {
      final path = harness.fixturePath(
        FixtureKeys.reflowableEpub,
        reason: 'Fixture ${FixtureKeys.reflowableEpub} missing from asset bundle',
      );
      final pub = await harness.reader.openPublication(path);

      final locators = <Locator>[];
      final sub = harness.reader.onTextLocatorChanged.listen(locators.add);
      addTearDown(sub.cancel);

      await tester.pumpWidget(bareReaderApp(pub));
      await waitWithPump(
        tester,
        () => locators.isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'No initial locator before applying preferences',
      );
      final beforePreferences = locators.last;

      await expectLater(
        harness.reader.setEPUBPreferences(EPUBPreferences(fontSize: 2.0)),
        completes,
        reason: 'setEPUBPreferences should not throw',
      );

      await harness.reader.goForward();
      await waitWithPump(
        tester,
        () => locators.last != beforePreferences,
        timeout: const Duration(seconds: 30),
        reason: 'Reader stopped emitting locators after setEPUBPreferences',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'setPDFPreferences applies and reader continues emitting page locators',
      (tester) async {
        final path = harness.fixturePath(
          FixtureKeys.timeMachinePdf,
          reason: 'Fixture ${FixtureKeys.timeMachinePdf} missing from asset bundle',
        );
        final pub = await harness.reader.openPublication(path);

        final locators = <Locator>[];
        final sub = harness.reader.onTextLocatorChanged.listen(locators.add);
        addTearDown(sub.cancel);

        await tester.pumpWidget(bareReaderApp(pub));
        await waitWithPump(
          tester,
          () => locators.isNotEmpty,
          timeout: const Duration(seconds: 30),
          reason: 'No initial locator before applying PDF preferences',
        );

        await expectLater(
          harness.reader.setPDFPreferences(const PDFPreferences(layout: PDFLayout.scrollVertical)),
          completes,
          reason: 'setPDFPreferences should not throw',
        );
        await waitForListStable(tester, locators);
        final beforeNavigation = locators.last.locations?.position;

        await harness.reader.goForward();
        await waitWithPump(
          tester,
          () => locators.last.locations?.position != beforeNavigation,
          timeout: const Duration(seconds: 15),
          reason: 'Reader stopped emitting page locators after setPDFPreferences',
        );

        await tester.pumpWidget(const SizedBox());
      },
      skip: kIsWeb,
    );

    testWidgets('applyDecorations applies, replaces, and clears a highlight group', (tester) async {
      final path = harness.fixturePath(
        FixtureKeys.reflowableEpub,
        reason: 'Fixture ${FixtureKeys.reflowableEpub} missing from asset bundle',
      );
      final pub = await harness.reader.openPublication(path);

      final locators = <Locator>[];
      final sub = harness.reader.onTextLocatorChanged.listen(locators.add);
      addTearDown(sub.cancel);

      await tester.pumpWidget(bareReaderApp(pub));
      await waitWithPump(
        tester,
        () => locators.isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'No initial locator before applying decorations',
      );

      final firstDecoration = ReaderDecoration(
        id: 'd1',
        locator: locators.last,
        style: const ReaderDecorationStyle(style: DecorationStyle.highlight, tint: Colors.yellow),
      );
      final replacementDecoration = ReaderDecoration(
        id: 'd1',
        locator: locators.last,
        style: const ReaderDecorationStyle(style: DecorationStyle.highlight, tint: Colors.green),
      );

      await expectLater(
        harness.reader.applyDecorations('test-highlights', [firstDecoration]),
        completes,
        reason: 'applyDecorations should apply a highlight without throwing',
      );
      await expectLater(
        harness.reader.applyDecorations('test-highlights', [replacementDecoration]),
        completes,
        reason: 'applyDecorations should replace a highlight group without throwing',
      );
      await expectLater(
        harness.reader.applyDecorations('test-highlights', const []),
        completes,
        reason: 'applyDecorations should clear a highlight group without throwing',
      );

      await tester.pumpWidget(const SizedBox());
    });

    group(
      'EPUB image resource API',
      skip: kIsWeb ? 'Native-bundled illustrated fixture not available on web' : null,
      () {
        test('getResourceUrl returns a file URL to a cached, decodable image', () async {
          final path = harness.fixturePath(
            FixtureKeys.peterRabbitEpub,
            reason: 'Fixture ${FixtureKeys.peterRabbitEpub} missing',
          );

          final pub = await harness.reader.openPublication(path);

          final imageLink = pub.resources.firstWhere(
            (l) =>
                l.type?.startsWith('image/') == true ||
                (l.href.contains('.png') || l.href.contains('.jpg') || l.href.contains('.jpeg')),
            orElse: () => throw StateError(
              '${FixtureKeys.peterRabbitEpub} has no image resources - cannot test getResourceUrl',
            ),
          );

          final url = await harness.reader.getResourceUrl(imageLink.href);
          await expectNativeFileImageDecodes(url, href: imageLink.href);
        });
      },
    );
  });
}
