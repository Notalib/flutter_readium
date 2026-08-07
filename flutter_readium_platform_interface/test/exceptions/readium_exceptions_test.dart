import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadiumError equality', () {
    test('two errors with equal details are equal and share a hashCode', () {
      final a = ReadiumError('boom', code: 'notFound', details: {'href': '/a.epub'});
      final b = ReadiumError('boom', code: 'notFound', details: {'href': '/a.epub'});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('errors with different details are not equal', () {
      final a = ReadiumError('boom', code: 'notFound', details: {'href': '/a.epub'});
      final b = ReadiumError('boom', code: 'notFound', details: {'href': '/b.epub'});

      expect(a, isNot(b));
    });
  });

  group('ReadiumError.details immutability', () {
    test('mutating the map passed to the constructor does not affect the error', () {
      final source = {'href': '/a.epub'};
      final error = ReadiumError('boom', details: source);

      source['href'] = '/mutated.epub';

      expect(error.details, {'href': '/a.epub'});
    });

    test('mutating the exposed details map throws', () {
      final error = ReadiumError('boom', details: {'href': '/a.epub'});

      expect(() => error.details!['href'] = '/mutated.epub', throwsUnsupportedError);
    });

    test('fromJson produces unmodifiable details', () {
      final error = ReadiumError.fromJson({
        'message': 'boom',
        'code': 'notFound',
        'data': {'href': '/a.epub'},
      });

      expect(() => error.details!['href'] = '/mutated.epub', throwsUnsupportedError);
    });
  });
}
