// This file is the entry point for `flutter drive` which is used to run
// integration tests on web (via ChromeDriver). On native platforms,
// `flutter test integration_test` is used directly instead.
//
// Usage (aggregator = one build; or point --target at a single groups/*_test.dart):
//   chromedriver --port=4444 &
//   flutter drive --driver=test_driver/integration_test.dart \
//                 --target=integration_test/plugin_integration_test.dart \
//                 -d web-server

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

import 'web_fixture_server.dart';

Future<void> main() async {
  final server = await startWebFixtureServer(Directory('web/test-fixtures'));
  await integrationDriver(
    responseDataCallback: (data) async {
      // integrationDriver exits the process; a finally block cannot close on success.
      await server.close(force: true);
      reportTestResults(data);
    },
  );
}

void reportTestResults(Map<String, dynamic>? data) {
  final testCount = data?['testCount'];
  final testNames = data?['testNames'];
  if (testCount is! int || testCount == 0 || testNames is! List || testNames.length != testCount) {
    throw StateError('No valid integration test results were reported');
  }

  print('$testCount integration tests passed:');
  for (final testName in testNames) {
    print('  PASS $testName');
  }
}
