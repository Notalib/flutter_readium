import 'package:flutter/foundation.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';

import 'groups/warm_up.dart';
import 'readium_integration_harness.dart';

// Set once by [beginAggregatedRun]; non-null means "aggregate mode" so each suite's main() reuses the shared harness.
ReadiumIntegrationHarness? _aggregatedHarness;

bool _logListenerAttached = false;

// Route Dart-side logsto the test console. Integration tests don't run the example app's main(), which is where
// the app normally attaches this listener — so without it, setLogLevel(debug) records are generated and then dropped.
void _attachLogListener() {
  if (_logListenerAttached) return;
  _logListenerAttached = true;
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) => debugPrint(ReadiumLog.format(record, colored: !kIsWeb)));
}

/// Wires a single shared harness (fixtures, teardown, once-first warm-up) for an aggregated run.
/// Called once by `plugin_integration_test.dart`, the single CI entrypoint.
void beginAggregatedRun() {
  _aggregatedHarness = _setUpHarness(warmUp: true);
}

/// The harness for the current suite. In an aggregated run this is the shared harness from [beginAggregatedRun];
/// when a suite file is run on its own (e.g. the VSCode per-test gutter button) it wires its own harness.
ReadiumIntegrationHarness suiteHarness({bool warmUp = true}) => _aggregatedHarness ?? _setUpHarness(warmUp: warmUp);

ReadiumIntegrationHarness _setUpHarness({required bool warmUp}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _attachLogListener();

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
