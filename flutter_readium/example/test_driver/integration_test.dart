// This file is the entry point for `flutter drive` which is used to run
// integration tests on web (via ChromeDriver). On native platforms,
// `flutter test integration_test` is used directly instead.
//
// Usage:
//   chromedriver --port=4444 &
//   flutter drive --driver=test_driver/integration_test.dart \
//                 --target=integration_test/plugin_integration_test.dart \
//                 -d chrome

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
