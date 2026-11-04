import 'package:flutter/services.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_readium/reader_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReadiumReaderChannel channelWith(
    void Function(InternalLinkEvent) onInternalLinkActivated,
  ) => ReadiumReaderChannel(
    'test',
    onReaderReady: () {},
    onPageChanged: (_) {},
    onInternalLinkActivated: onInternalLinkActivated,
  );

  test('onInternalLinkActivated decodes locator and link json strings', () async {
    InternalLinkEvent? received;
    final channel = channelWith((final event) => received = event);

    await channel.onMethodCall(
      const MethodCall('onInternalLinkActivated', {
        'from': '{"href":"ch1.xhtml","type":"application/xhtml+xml","locations":{"progression":0.5}}',
        'target': '{"href":"notes.xhtml#n1","type":"application/xhtml+xml"}',
      }),
    );

    expect(received!.from?.href, 'ch1.xhtml');
    expect(received!.from?.locations?.progression, 0.5);
    expect(received!.target.href, 'notes.xhtml#n1');
  });

  test('onInternalLinkActivated accepts a missing from locator', () async {
    InternalLinkEvent? received;
    final channel = channelWith((final event) => received = event);

    await channel.onMethodCall(
      const MethodCall('onInternalLinkActivated', {
        'from': null,
        'target': '{"href":"notes.xhtml#n1","type":"application/xhtml+xml"}',
      }),
    );

    expect(received!.from, isNull);
    expect(received!.target.href, 'notes.xhtml#n1');
  });
}
