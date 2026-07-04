import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

import '../readium_integration_harness.dart';

void defineErrorHandlingTests(ReadiumIntegrationHarness harness) {
  group('Error handling', () {
    test(
      'openPublication throws ReadiumException for an invalid native path',
      skip: kIsWeb ? 'Error path differs on web (HTTP fetch vs file I/O)' : null,
      () async {
        await expectLater(
          harness.readium.openPublication('/does-not-exist/no-such.epub'),
          throwsA(isA<ReadiumException>()),
        );
      },
    );

    test(
      'onErrorEvent emits when opening an unreachable web publication',
      skip: kIsWeb ? null : 'Web-specific HTTP error event path',
      () async {
        final errors = <ReadiumError>[];
        final sub = harness.readium.onErrorEvent.listen(errors.add);
        addTearDown(sub.cancel);

        try {
          await harness.readium.openPublication('/no-such-fixture/manifest.json');
        } on Object {
          // Expected: open fails; this test asserts the error event stream.
        }

        await waitUntil(
          () => errors.isNotEmpty,
          timeout: const Duration(seconds: 15),
          reason: 'onErrorEvent did not emit after a failed openPublication',
        );
      },
    );
  });
}
