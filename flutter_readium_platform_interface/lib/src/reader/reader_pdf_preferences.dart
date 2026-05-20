import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../index.dart';

@immutable
class PDFPreferences with EquatableMixin implements JSONable {
  const PDFPreferences({
    this.scroll,
    this.readingProgression,
  });

  /// Whether to use a continuous scroll layout instead of paginated.
  final bool? scroll;

  /// Direction of the reading progression.
  final PDFReadingProgression? readingProgression;

  factory PDFPreferences.fromJson(Map<String, dynamic> json) {
    final scroll = json['scroll'] as bool?;
    final rpStr = json['readingProgression'] as String?;
    return PDFPreferences(
      scroll: scroll,
      readingProgression: rpStr != null ? PDFReadingProgression.fromJson(rpStr) : null,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{}
    ..putOpt('scroll', scroll)
    ..putOpt('readingProgression', readingProgression?.toJson());

  PDFPreferences copyWith({
    bool? scroll,
    PDFReadingProgression? readingProgression,
  }) =>
      PDFPreferences(
        scroll: scroll ?? this.scroll,
        readingProgression: readingProgression ?? this.readingProgression,
      );

  @override
  List<Object?> get props => [scroll, readingProgression];
}

enum PDFReadingProgression {
  ltr,
  rtl;

  static PDFReadingProgression? fromJson(String? value) {
    switch (value) {
      case 'ltr':
        return PDFReadingProgression.ltr;
      case 'rtl':
        return PDFReadingProgression.rtl;
      default:
        return null;
    }
  }

  String toJson() {
    switch (this) {
      case PDFReadingProgression.ltr:
        return 'ltr';
      case PDFReadingProgression.rtl:
        return 'rtl';
    }
  }
}
