import 'package:flutter/services.dart';
import 'package:flutter_readium_lcp/flutter_readium_lcp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LcpAcquiredPublication', () {
    test('round-trips through json', () {
      const acquired = LcpAcquiredPublication(
        path: '/data/acquired/id.epub',
        fileName: 'id.epub',
        licenseId: 'id',
        mediaType: 'application/epub+zip',
        fileExtension: 'epub',
      );
      final copy = LcpAcquiredPublication.fromJson(acquired.toJson());
      expect(copy.path, acquired.path);
      expect(copy.fileName, 'id.epub');
      expect(copy.licenseId, 'id');
      expect(copy.mediaType, 'application/epub+zip');
      expect(copy.fileExtension, 'epub');
    });

    test('media type and extension are optional', () {
      final acquired = LcpAcquiredPublication.fromJson({'path': '/p', 'fileName': 'f', 'licenseId': 'l'});
      expect(acquired.mediaType, isNull);
      expect(acquired.fileExtension, isNull);
    });
  });

  group('LcpLicenseInfo', () {
    test('reads every field', () {
      final info = LcpLicenseInfo.fromJson({
        'licenseId': 'abc',
        'provider': 'https://provider.example',
        'issued': '2026-01-01T00:00:00Z',
        'updated': '2026-01-02T00:00:00.500Z',
        'rightsStart': '2026-02-01T00:00:00Z',
        'rightsEnd': '2026-03-01T00:00:00Z',
        'copyLimit': 1000,
        'printLimit': 10,
        'charactersToCopyLeft': 900,
        'pagesToPrintLeft': 8,
        'state': 'active',
        'statusMessage': 'ok',
        'statusUpdated': '2026-01-03T00:00:00Z',
      });
      expect(info.licenseId, 'abc');
      expect(info.provider, 'https://provider.example');
      expect(info.issued, DateTime.utc(2026));
      expect(info.updated, DateTime.utc(2026, 1, 2, 0, 0, 0, 500));
      expect(info.rightsStart, DateTime.utc(2026, 2));
      expect(info.rightsEnd, DateTime.utc(2026, 3));
      expect(info.copyLimit, 1000);
      expect(info.printLimit, 10);
      expect(info.charactersToCopyLeft, 900);
      expect(info.pagesToPrintLeft, 8);
      expect(info.state, LcpLicenseState.active);
      expect(info.statusMessage, 'ok');
      expect(info.statusUpdated, DateTime.utc(2026, 1, 3));
    });

    test('optional fields may be absent', () {
      final info = LcpLicenseInfo.fromJson({
        'licenseId': 'abc',
        'provider': 'p',
        'issued': '2026-01-01T00:00:00Z',
        'updated': '2026-01-01T00:00:00Z',
      });
      expect(info.rightsEnd, isNull);
      expect(info.copyLimit, isNull);
      expect(info.charactersToCopyLeft, isNull);
      expect(info.state, isNull);
    });

    test('an unknown status state becomes null', () {
      final info = LcpLicenseInfo.fromJson({
        'licenseId': 'a',
        'provider': 'p',
        'issued': '2026-01-01T00:00:00Z',
        'updated': '2026-01-01T00:00:00Z',
        'state': 'newState',
      });
      expect(info.state, isNull);
    });

    test('round-trips through json', () {
      final info = LcpLicenseInfo.fromJson({
        'licenseId': 'a',
        'provider': 'p',
        'issued': '2026-01-01T00:00:00Z',
        'updated': '2026-01-01T00:00:00Z',
        'copyLimit': 5,
        'state': 'revoked',
      });
      final copy = LcpLicenseInfo.fromJson(info.toJson());
      expect(copy.licenseId, 'a');
      expect(copy.issued, info.issued);
      expect(copy.copyLimit, 5);
      expect(copy.state, LcpLicenseState.revoked);
    });
  });

  group('FlutterReadiumLcp channel calls', () {
    const channel = MethodChannel('test/flutter_readium_lcp_models');
    late FlutterReadiumLcp lcp;

    setUp(() => lcp = FlutterReadiumLcp.forTesting(channel));

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    void mockNative(final Future<Object?> Function(MethodCall call) handler) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler);

    Future<void> nativeReportsProgress(final int id, final double progress) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('acquisitionProgress', {'id': id, 'progress': progress})),
        (_) {},
      );
    }

    test('acquirePublication forwards the path and returns the model', () async {
      MethodCall? seen;
      mockNative((final call) async {
        seen = call;
        return {'path': '/acquired/id.epub', 'fileName': 'id.epub', 'licenseId': 'id'};
      });
      final acquired = await lcp.acquirePublication('/in/book.lcpl');
      expect(seen!.method, 'acquirePublication');
      expect((seen!.arguments as Map)['lcplPath'], '/in/book.lcpl');
      expect((seen!.arguments as Map)['progressId'], isNull);
      expect(acquired.path, '/acquired/id.epub');
    });

    test('acquirePublication delivers progress to its own callback and stops afterwards', () async {
      final seen = <double>[];
      int? progressId;
      mockNative((final call) async {
        progressId = (call.arguments as Map)['progressId'] as int?;
        await nativeReportsProgress(progressId!, 0.25);
        return {'path': '/p', 'fileName': 'f', 'licenseId': 'l'};
      });
      await lcp.acquirePublication('/in/book.lcpl', onProgress: seen.add);
      await nativeReportsProgress(progressId!, 0.5);
      expect(seen, [0.25]);
    });

    test('a native failure becomes the typed LCP exception', () async {
      mockNative((final call) async {
        throw PlatformException(code: LcpErrorCodes.network, message: 'down', details: {'reason': 'network'});
      });
      await expectLater(lcp.acquirePublication('/x.lcpl'), throwsA(isA<LcpNetworkException>()));
      await expectLater(lcp.getLicenseInfo('/x.epub'), throwsA(isA<LcpNetworkException>()));
    });

    test('a failure without an LCP code stays a ReadiumException', () async {
      mockNative((final call) async {
        throw PlatformException(code: 'somethingElse', message: 'nope');
      });
      await expectLater(lcp.getLicenseInfo('/x.epub'), throwsA(isNot(isA<LcpException>())));
    });

    test('getLicenseInfo forwards the path and parses the reply', () async {
      MethodCall? seen;
      mockNative((final call) async {
        seen = call;
        return {
          'licenseId': 'abc',
          'provider': 'p',
          'issued': '2026-01-01T00:00:00Z',
          'updated': '2026-01-01T00:00:00Z',
        };
      });
      final info = await lcp.getLicenseInfo('/book.epub');
      expect((seen!.arguments as Map)['path'], '/book.epub');
      expect(info.licenseId, 'abc');
    });
  });
}
