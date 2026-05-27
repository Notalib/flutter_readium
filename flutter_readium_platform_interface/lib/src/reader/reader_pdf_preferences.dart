import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../index.dart';

@immutable
class PDFPreferences with EquatableMixin implements JSONable {
  const PDFPreferences({this.layout, this.readingProgression, this.pageSpacing, this.fit});

  factory PDFPreferences.fromJson(Map<String, dynamic> json) {
    final layoutStr = json['layout'] as String?;
    final rpStr = json['readingProgression'] as String?;
    final pageSpacingNum = json['pageSpacing'] as num?;
    final fitStr = json['fit'] as String?;
    return PDFPreferences(
      layout: layoutStr != null ? PDFLayout.fromJson(layoutStr) : null,
      readingProgression: rpStr != null ? PDFReadingProgression.fromJson(rpStr) : null,
      pageSpacing: pageSpacingNum?.toDouble(),
      fit: fitStr != null ? PDFFit.fromJson(fitStr) : null,
    );
  }

  /// Page layout / scroll mode. Unifies the iOS `scroll` + `scrollAxis` knobs
  /// and the Android Pdfium `scrollAxis` knob into one cross-platform setting.
  /// See [PDFLayout] for the per-platform mapping.
  final PDFLayout? layout;

  /// Direction of the reading progression.
  final PDFReadingProgression? readingProgression;

  /// Spacing between pages.
  ///
  /// - Supported on iOS and Android.
  /// - Ignored on web (PDF rendering is not supported on web).
  /// - Value must be >= 0.
  final double? pageSpacing;

  /// How pages should be fitted in the viewport.
  ///
  /// - iOS supports all values: [PDFFit.auto], [PDFFit.page], [PDFFit.width].
  /// - Android Pdfium supports [PDFFit.page] and [PDFFit.width].
  /// - Ignored on web (PDF rendering is not supported on web).
  final PDFFit? fit;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{}
    ..putOpt('layout', layout?.toJson())
    ..putOpt('readingProgression', readingProgression?.toJson())
    ..putOpt('pageSpacing', pageSpacing)
    ..putOpt('fit', fit?.toJson());

  PDFPreferences copyWith({
    PDFLayout? layout,
    PDFReadingProgression? readingProgression,
    double? pageSpacing,
    PDFFit? fit,
  }) => PDFPreferences(
    layout: layout ?? this.layout,
    readingProgression: readingProgression ?? this.readingProgression,
    pageSpacing: pageSpacing ?? this.pageSpacing,
    fit: fit ?? this.fit,
  );

  @override
  List<Object?> get props => [layout, readingProgression, pageSpacing, fit];
}

/// Page layout / scroll mode for PDF publications.
///
/// Platform mapping:
/// - [paginated]
///   - iOS (PDFKit): `scroll = false` — true paginated mode with page-flip
///     animation and snap.
///   - Android (Pdfium): `scrollAxis = horizontal` — Pdfium has no paginated
///     mode, but a single-page-wide viewport gives one-page-per-swipe
///     navigation as the closest equivalent.
/// - [scrollVertical]
///   - iOS: `scroll = true, scrollAxis = vertical`.
///   - Android: `scrollAxis = vertical`.
/// - [scrollHorizontal]
///   - iOS: `scroll = true, scrollAxis = horizontal`.
///   - Android: `scrollAxis = horizontal` (same wire mapping as [paginated]
///     but kept distinct because iOS treats the two differently).
enum PDFLayout {
  paginated,
  scrollVertical,
  scrollHorizontal;

  static PDFLayout? fromJson(String? value) {
    switch (value) {
      case 'paginated':
        return PDFLayout.paginated;
      case 'scrollVertical':
        return PDFLayout.scrollVertical;
      case 'scrollHorizontal':
        return PDFLayout.scrollHorizontal;
      default:
        return null;
    }
  }

  String toJson() {
    switch (this) {
      case PDFLayout.paginated:
        return 'paginated';
      case PDFLayout.scrollVertical:
        return 'scrollVertical';
      case PDFLayout.scrollHorizontal:
        return 'scrollHorizontal';
    }
  }
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

/// Method for fitting PDF pages within the viewport.
///
/// Platform mapping:
/// - [auto]
///   - iOS: `fit = auto`.
///   - Android: ignored (`PdfiumPreferences` supports only page/width fit).
/// - [page]
///   - iOS: `fit = page`.
///   - Android: `fit = contain` (closest equivalent).
/// - [width]
///   - iOS: `fit = width`.
///   - Android: `fit = width`.
enum PDFFit {
  auto,
  page,
  width;

  static PDFFit? fromJson(String? value) {
    switch (value) {
      case 'auto':
        return PDFFit.auto;
      case 'page':
        return PDFFit.page;
      case 'width':
        return PDFFit.width;
      default:
        return null;
    }
  }

  String toJson() {
    switch (this) {
      case PDFFit.auto:
        return 'auto';
      case PDFFit.page:
        return 'page';
      case PDFFit.width:
        return 'width';
    }
  }
}
