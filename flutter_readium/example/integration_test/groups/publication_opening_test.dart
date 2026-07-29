import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_suite_setup.dart';
import '../test_fixtures.dart';

void main() {
  final harness = suiteHarness();

  group('Publication opening contract', () {
    test('opens EPUB successfully', () async {
      final path = harness.fixturePath(
        FixtureKeys.reflowableEpub,
        reason: 'Fixture ${FixtureKeys.reflowableEpub} missing from asset bundle',
      );

      final pub = await harness.readium.openPublication(path);

      expect(pub.metadata.title, isNotEmpty);
      expect(pub.readingOrder, isNotEmpty);
      expect(pub.containsMediaOverlays, isFalse, reason: 'Plain EPUB should not report media overlays');
    });

    test(
      'opens PDF successfully',
      skip: kIsWeb ? 'PDF not supported on web' : null,
      () async {
        final path = harness.fixturePath(
          FixtureKeys.pdfTest,
          reason: 'Fixture ${FixtureKeys.pdfTest} missing from asset bundle',
        );

        final pub = await harness.readium.openPublication(path);

        expect(pub.metadata.title, isNotEmpty);
        expect(pub.readingOrder, isNotEmpty);
        expect(pub.conformsToReadiumPDF, isTrue, reason: 'PDF fixture should conform to the Readium PDF profile');
      },
    );

    test('opens WebPub with media overlays', () async {
      final path = harness.fixturePath(
        FixtureKeys.overlayWebpub,
        reason: 'Fixture ${FixtureKeys.overlayWebpub} missing from asset bundle',
      );

      final pub = await harness.readium.openPublication(path);

      expect(pub.readingOrder, isNotEmpty);
      expect(pub.containsMediaOverlays, isTrue, reason: 'Overlay webpub should report media overlays');
    });

    test('opens audiobook', () async {
      final path = harness.fixturePath(
        FixtureKeys.audiobook,
        reason: 'Fixture ${FixtureKeys.audiobook} missing from asset bundle',
      );

      final pub = await harness.readium.openPublication(path);

      expect(pub.readingOrder, isNotEmpty);
      expect(
        pub.conformsToReadiumAudiobook,
        isTrue,
        reason: 'Audiobook fixture should conform to the Readium audiobook profile',
      );
    });

    test(
      'opens DiViNa comic',
      () async {
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
      },
    );

    group('Publication shapes', () {
      test('opens fixed-layout EPUB', () async {
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
      });

      test('opens guided-navigation publication', () async {
        final path = harness.fixturePath(
          FixtureKeys.guidedNav,
          reason: 'Fixture ${FixtureKeys.guidedNav} missing',
        );

        final pub = await harness.readium.openPublication(path);
        expect(pub.readingOrder, isNotEmpty);
      });

      test('opens comic media-overlay EPUB', () async {
        final path = harness.fixturePath(
          FixtureKeys.comic,
          reason: 'Fixture ${FixtureKeys.comic} missing',
        );

        final pub = await harness.readium.openPublication(path);

        expect(pub.readingOrder, isNotEmpty);
        expect(
          pub.containsMediaOverlays,
          isTrue,
          reason: 'Comic fixture should report media overlays',
        );
      });
    });
  });
}
