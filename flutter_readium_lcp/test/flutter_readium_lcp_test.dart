import 'package:flutter/services.dart';
import 'package:flutter_readium_lcp/flutter_readium_lcp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/flutter_readium_lcp');
  late FlutterReadiumLcp lcp;

  setUp(() {
    lcp = FlutterReadiumLcp.forTesting(channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<Object?> nativeAsksPassphrase(final Map<String, Object?> args) async {
    final reply = await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('requestPassphrase', args)),
      null,
    );
    return channel.codec.decodeEnvelope(reply!);
  }

  const request = {
    'reason': 'invalid',
    'hint': 'your cat',
    'hintUrl': 'https://example.com/hint',
    'provider': 'https://provider.example',
    'licenseId': 'abc',
  };

  test('passes the request to the provider and returns its passphrase', () async {
    LcpPassphraseRequest? seen;
    lcp.setPassphraseProvider((final r) async {
      seen = r;
      return 'secret';
    });

    expect(await nativeAsksPassphrase(request), 'secret');
    expect(seen!.reason, LcpPassphraseReason.invalid);
    expect(seen!.hint, 'your cat');
    expect(seen!.hintUrl, 'https://example.com/hint');
    expect(seen!.provider, 'https://provider.example');
    expect(seen!.licenseId, 'abc');
  });

  test('a cancelled prompt returns null', () async {
    lcp.setPassphraseProvider((final _) async => null);
    expect(await nativeAsksPassphrase(request), isNull);
  });

  test('no provider returns null', () async {
    lcp.setPassphraseProvider(null);
    expect(await nativeAsksPassphrase(request), isNull);
  });

  test('a throwing provider counts as cancelled', () async {
    lcp.setPassphraseProvider((final _) async => throw Exception('boom'));
    expect(await nativeAsksPassphrase(request), isNull);
  });

  test('reason defaults to notFound and optional fields may be absent', () async {
    LcpPassphraseRequest? seen;
    lcp.setPassphraseProvider((final r) async {
      seen = r;
      return null;
    });
    await nativeAsksPassphrase({'hint': 'h', 'provider': 'p', 'licenseId': 'l'});
    expect(seen!.reason, LcpPassphraseReason.notFound);
    expect(seen!.hintUrl, isNull);
  });

  test('isAvailable asks native', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (final call) async => call.method == 'isAvailable' ? true : null,
    );
    expect(await lcp.isAvailable(), isTrue);
  });

  group('without a native plugin (web)', () {
    // No mock handler on the channel: the binary messenger answers with MissingPluginException.
    test('isAvailable is false', () async {
      expect(await lcp.isAvailable(), isFalse);
    });

    test('acquirePublication throws UnsupportedError', () async {
      await expectLater(lcp.acquirePublication('/x.lcpl'), throwsUnsupportedError);
    });

    test('getLicenseInfo throws UnsupportedError', () async {
      await expectLater(lcp.getLicenseInfo('/x.epub'), throwsUnsupportedError);
    });
  });
}
