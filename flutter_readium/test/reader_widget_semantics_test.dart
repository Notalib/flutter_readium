import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ReadiumReaderWidget excludes content semantics only when screen reader navigation is off', (
    tester,
  ) async {
    final publication = Publication.fromJson({
      'metadata': {'title': 't'},
      'links': <dynamic>[],
      'readingOrder': <dynamic>[],
    })!;

    for (final allow in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: ReadiumReaderWidget(
            key: ValueKey(allow),
            publication: publication,
            allowScreenReaderNavigation: allow,
          ),
        ),
      );
      final excluding = tester.widget<ExcludeSemantics>(
        find.descendant(of: find.byType(ReadiumReaderWidget), matching: find.byType(ExcludeSemantics)),
      );
      expect(excluding.excluding, !allow);
    }
  });
}
