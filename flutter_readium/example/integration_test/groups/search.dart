import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';

import '../support/readium_integration_harness.dart';
import '../test_fixtures.dart';

void defineSearchTests(ReadiumIntegrationHarness harness) {
  group('Search', () {
    test(
      'searchInPublication returns hits for a common word in a reflowable EPUB',
      skip: kIsWeb ? 'searchInPublication not implemented on web (see docs/parity/web-search.md)' : false,
      () async {
        final path = harness.fixturePath(
          FixtureKeys.reflowableEpub,
          reason: 'Fixture ${FixtureKeys.reflowableEpub} missing from asset bundle',
        );

        await harness.reader.openPublication(path);

        final results = await harness.reader.searchInPublication('og');
        expect(results, isNotEmpty, reason: '"og" should yield matches in the Danish EPUB');
        expect(results.first.locator.href, isNotEmpty);
      },
    );

    test(
      'searchInPublication returns no hits for an absent word in a reflowable EPUB',
      skip: kIsWeb ? 'searchInPublication not implemented on web (see docs/parity/web-search.md)' : false,
      () async {
        final path = harness.fixturePath(
          FixtureKeys.reflowableEpub,
          reason: 'Fixture ${FixtureKeys.reflowableEpub} missing from asset bundle',
        );

        await harness.reader.openPublication(path);

        final results = await harness.reader.searchInPublication('zzzxxy-not-a-word');
        expect(results, isEmpty, reason: 'An absent search term should return an empty result set');
      },
    );

    test(
      'searchInPublication returns hits for a common word in a text PDF',
      () async {
        final path = harness.fixturePath(
          FixtureKeys.timeMachinePdf,
          reason: 'Fixture ${FixtureKeys.timeMachinePdf} missing from asset bundle',
        );

        await harness.reader.openPublication(path);

        final results = await harness.reader.searchInPublication('time');
        expect(results, isNotEmpty, reason: '"time" should yield matches in The Time Machine PDF');
        expect(results.first.locator.href, isNotEmpty);
        expect(
          results.first.locator.locations?.position,
          isNotNull,
          reason: 'PDF search hit should carry a 1-based page position',
        );
      },
      skip: kIsWeb || isAndroid()
          ? 'PDF text search not supported on Android (kotlin-toolkit has no PDF SearchService) or web'
          : false,
    );

    test(
      'searchInPublication returns no hits for an absent word in a text PDF',
      () async {
        final path = harness.fixturePath(
          FixtureKeys.timeMachinePdf,
          reason: 'Fixture ${FixtureKeys.timeMachinePdf} missing from asset bundle',
        );

        await harness.reader.openPublication(path);

        final results = await harness.reader.searchInPublication('zzzxxy-not-a-word');
        expect(results, isEmpty, reason: 'An absent PDF search term should return an empty result set');
      },
      skip: kIsWeb || isAndroid()
          ? 'PDF text search not supported on Android (kotlin-toolkit has no PDF SearchService) or web'
          : false,
    );
  });
}
