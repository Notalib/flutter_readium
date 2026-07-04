import 'package:flutter/widgets.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import '../readium_integration_harness.dart';
import '../test_fixtures.dart';

void defineWarmUpTests(ReadiumIntegrationHarness harness) {
  testWidgets(
    'Warm-up the platform reader view',
    (tester) async {
      final path = harness.fixturePath(
        FixtureKeys.warmupWebpub,
        reason: 'Fixture ${FixtureKeys.warmupWebpub} missing from asset bundle',
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
        timeout: const Duration(seconds: 120),
        reason: 'Reader never emitted an initial textLocator during warm-up',
        diagnostics: () => 'readerStatus=$readerStatus, locators=${locators.length}',
      );

      await tester.pumpWidget(const SizedBox());
    },
  );
}
