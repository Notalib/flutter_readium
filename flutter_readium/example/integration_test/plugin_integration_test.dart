// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_readium_example/state/publication_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_readium/flutter_readium.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('openPublication exceptions', () async {
    // TODO: Fix this, get err Storage was accessed before it was initialized.
    // see https://github.com/felangel/bloc/blob/master/examples/flutter_weather/test/helpers/hydrated_bloc.dart
    final PublicationBloc bloc = PublicationBloc();

    expect(
      () => bloc.add(OpenPublication(publicationUrl: "asd")),
      throwsA(isA<ReadiumException>),
    );
  });

  testWidgets('getPlatformVersion test', (WidgetTester tester) async {
    final FlutterReadium plugin = FlutterReadium();
    final Publication publication = await plugin.openPublication("pubUrl");
    // The version string depends on the host platform running the test, so
    // just assert that some non-empty string is returned.
    expect(publication, true);
  });
}
