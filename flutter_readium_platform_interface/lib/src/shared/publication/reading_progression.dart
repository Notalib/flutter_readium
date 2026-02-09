import 'package:fimber/fimber.dart';

import 'presentation/presentation.dart';
import 'publication.dart';

/// Direction of the [Publication] reading progression.
enum ReadingProgression {
  /// Left-to-right reading progression.
  ltr,

  /// Right-to-left reading progression.
  rtl,

  /// Top to bottom reading progression.
  ttb,

  /// Bottom to top reading progression.
  btt,
  auto;

  factory ReadingProgression.fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'ltr':
        return ReadingProgression.ltr;
      case 'rtl':
        return ReadingProgression.rtl;
      case 'ttb':
        return ReadingProgression.ttb;
      case 'btt':
        return ReadingProgression.btt;
      case 'auto':
        return ReadingProgression.auto;
      default:
        Fimber.w('Unknown reading progression: $value, defaulting to auto');
        return ReadingProgression.auto;
    }
  }

  /// Returns the leading [Page] for the [ReadingProgression].
  PresentationPage get leadingPage {
    switch (this) {
      case ReadingProgression.ltr:
        return PresentationPage.left;
      case ReadingProgression.rtl:
      default:
        return PresentationPage.right;
    }
  }

  /// Indicates whether this reading progression is on the horizontal axis, or null if unknown.
  bool? isHorizontal() {
    switch (this) {
      case ReadingProgression.rtl:
      case ReadingProgression.ltr:
        return true;
      case ReadingProgression.ttb:
      case ReadingProgression.btt:
        return false;
      case ReadingProgression.auto:
        return null;
    }
  }

  /// Indicates whether items in this reading progression must be placed in natural or reverse order in the webviews
  bool isReverseOrder() {
    switch (this) {
      case ReadingProgression.rtl:
      case ReadingProgression.btt:
        return true;
      case ReadingProgression.ltr:
      case ReadingProgression.ttb:
        return false;
      case ReadingProgression.auto: // Don't know exactly what this means ;-)
        return false;
    }
  }
}
