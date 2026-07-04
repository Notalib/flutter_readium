// Integration tests for the Dart -> native/web Readium contract.
//
// Keep this file as the single integration-test entrypoint so the iOS/webview
// warm-up runs once and first. Domain-specific tests live in groups/.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:integration_test/integration_test.dart';

import 'groups/error_handling.dart';
import 'groups/navigation_locator.dart';
import 'groups/preferences_decorations_resources.dart';
import 'groups/publication_opening.dart';
import 'groups/reader_widget_lifecycle.dart';
import 'groups/search.dart';
import 'groups/timebased_playback.dart';
import 'groups/warm_up.dart';
import 'readium_integration_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final harness = ReadiumIntegrationHarness();

  setUpAll(() async {
    await harness.readium.setLogLevel(LogLevel.debug);
    await harness.loadFixtures();
  });

  tearDown(() async {
    await harness.closePublication();
  });

  defineWarmUpTests(harness);
  definePublicationOpeningTests(harness);
  defineReaderWidgetLifecycleTests(harness);
  defineNavigationLocatorTests(harness);
  definePreferencesDecorationsResourcesTests(harness);
  defineSearchTests(harness);
  defineTimebasedPlaybackTests(harness);
  defineErrorHandlingTests(harness);
}
