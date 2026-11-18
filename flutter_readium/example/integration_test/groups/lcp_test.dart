// LCP open flow against the generated basic-profile fixtures. Run on its own, not from the CI entrypoint:
//   flutter test integration_test/groups/lcp_test.dart -d <device>
// It needs `bin/build_lcp_test_fixtures` to have run before the app build, and no stored passphrase:
// the tests run in order and the last one stores it. Reset it first (iOS: `xcrun simctl keychain booted
// reset`; Android: `adb shell pm clear com.example.flutter_readium_example`).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_readium_example/utils/publication_utils.dart';
import 'package:flutter_readium_lcp/flutter_readium_lcp.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_suite_setup.dart';

// Public test value from bin/build_lcp_test_fixtures, not a secret.
const _passphrase = 'flutter-readium-lcp-test';
const _fixture = 'lcp_peter_rabbit.epub';

void main() {
  final harness = suiteHarness(warmUp: false);
  final lcp = FlutterReadiumLcp();

  Future<String> fixturePath() async {
    final path = await PublicationUtils.lcpFixturePath(_fixture);
    expect(path, isNotNull, reason: '$_fixture missing. Run bin/build_lcp_test_fixtures and rebuild the app.');
    return path!;
  }

  tearDown(() => lcp.setPassphraseProvider(null));

  group('LCP', () {
    testWidgets('the add-on reports LCP as available', skip: kIsWeb, (_) async {
      expect(await lcp.isAvailable(), isTrue);
    });

    testWidgets('loadPublication returns metadata without asking for a passphrase', skip: kIsWeb, (_) async {
      final requests = <LcpPassphraseRequest>[];
      lcp.setPassphraseProvider((final request) async {
        requests.add(request);
        return _passphrase;
      });

      final pub = await harness.readium.loadPublication(await fixturePath());

      expect(pub.metadata.title, isNotEmpty);
      expect(requests, isEmpty);
    });

    testWidgets('openPublication fails with the typed error when the prompt is cancelled', skip: kIsWeb, (_) async {
      lcp.setPassphraseProvider((final _) async => null);

      await expectLater(
        harness.readium.openPublication(await fixturePath()),
        throwsA(
          predicate(
            (final e) =>
                e is ReadiumException && LcpException.fromReadiumException(e) is LcpPassphraseRequiredException,
          ),
        ),
      );
    });

    testWidgets('openPublication asks again after a wrong passphrase, then opens', skip: kIsWeb, (_) async {
      final requests = <LcpPassphraseRequest>[];
      lcp.setPassphraseProvider((final request) async {
        requests.add(request);
        return requests.length == 1 ? 'wrong passphrase' : _passphrase;
      });

      final pub = await harness.readium.openPublication(await fixturePath());

      expect(requests.map((final r) => r.reason), [LcpPassphraseReason.notFound, LcpPassphraseReason.invalid]);
      expect(pub.metadata.title, isNotEmpty);
      expect(pub.readingOrder, isNotEmpty);
    });
  });
}
