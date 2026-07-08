// Single integration-test entrypoint for CI: native
// `flutter test integration_test/plugin_integration_test.dart` and web
// `flutter drive --target=…/plugin_integration_test.dart`.
//
// One entrypoint = one app build (integration tests build one binary per target
// file — see flutter/flutter#115751), and the platform/webview warm-up runs
// once, first. Each suite under groups/ also has its own main() so it can be run
// standalone from the IDE with per-test gutter buttons; here we reuse those via
// a single shared harness (see suite_setup.dart).
//
// NOTE: run this file explicitly, not the folder glob `flutter test
// integration_test` — the glob would build every groups/*_test.dart as its own
// target too, multiplying the (slow) native build.

import 'groups/error_handling_test.dart' as error_handling;
import 'groups/navigation_locator_test.dart' as navigation_locator;
import 'groups/preferences_decorations_resources_test.dart' as preferences_decorations_resources;
import 'groups/publication_opening_test.dart' as publication_opening;
import 'groups/reader_widget_lifecycle_test.dart' as reader_widget_lifecycle;
import 'groups/search_test.dart' as search;
import 'groups/timebased_playback_test.dart' as timebased_playback;
import 'test_suite_setup.dart';

void main() {
  beginAggregatedRun();

  error_handling.main();
  navigation_locator.main();
  preferences_decorations_resources.main();
  publication_opening.main();
  reader_widget_lifecycle.main();
  search.main();
  timebased_playback.main();
}
