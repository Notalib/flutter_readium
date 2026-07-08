import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'groups/warm_up.dart';
import 'readium_integration_harness.dart';

// Set once by [beginAggregatedRun]; non-null means "aggregate mode" so each
// suite's main() reuses the shared harness instead of re-registering setup or
// re-warming. Process-scoped and write-once — no reset needed.
ReadiumIntegrationHarness? _aggregatedHarness;

/// Wires a single shared harness (fixtures, teardown, once-first warm-up) for an
/// aggregated run. Called once by `plugin_integration_test.dart`, the single
/// native/web CI entrypoint — one entrypoint keeps it to one app build.
void beginAggregatedRun() {
  _aggregatedHarness = _setUpHarness(warmUp: true);
}

/// The harness for the current suite. In an aggregated run this is the shared
/// harness from [beginAggregatedRun]; when a suite file is run on its own (e.g.
/// the VSCode per-test gutter button) it wires its own harness, warming up first.
ReadiumIntegrationHarness suiteHarness({bool warmUp = true}) => _aggregatedHarness ?? _setUpHarness(warmUp: warmUp);

ReadiumIntegrationHarness _setUpHarness({required bool warmUp}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final harness = ReadiumIntegrationHarness();

  setUpAll(() async {
    await harness.readium.setLogLevel(LogLevel.debug);
    await harness.loadFixtures();
  });

  tearDown(() async {
    await harness.closePublication();
  });

  if (warmUp) defineWarmUpTests(harness);

  return harness;
}
