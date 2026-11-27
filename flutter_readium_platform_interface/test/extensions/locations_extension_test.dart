import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocationExtension.progressionEnd', () {
    test('reads the value platforms send as a locations key', () {
      final locations = Locations.fromJson({'progression': 0.2, 'progressionEnd': 0.45});

      expect(locations.progressionEnd, 0.45);
      expect(locations.toJson()['progressionEnd'], 0.45);
    });

    test('accepts an integer from JSON', () {
      expect(Locations.fromJson({'progression': 0, 'progressionEnd': 1}).progressionEnd, 1.0);
    });

    test('is null when absent', () {
      expect(Locations.fromJson({'progression': 0.2}).progressionEnd, isNull);
    });
  });
}
