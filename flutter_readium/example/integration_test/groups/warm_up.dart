import 'package:flutter/widgets.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import '../readium_integration_harness.dart';
import '../test_fixtures.dart';

/// Forces the first platform-view / webview launch so the real tests don't pay that cost.
/// Best-effort: never fails on timeout — a cold CI simulator can thrash WebKit for minutes,
/// and first-locator emission is asserted for real by the reader-lifecycle suites.
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
        timeout: firstMountTimeout,
        reason: 'Reader never emitted an initial textLocator during warm-up',
        diagnostics: () => 'readerStatus=$readerStatus, locators=${locators.length}',
        failOnTimeout: false,
      );

      await tester.pumpWidget(const SizedBox());
    },
  );
}
