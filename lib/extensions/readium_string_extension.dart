import 'dart:convert';
import 'dart:ui';

extension ReadiumStringExtension on String {
  /// Only for debugging.
  /// Truncates a String with "…" if it's too long. Quotes and escapes the string.
  String truncateQuote(final int maxLength, {final int start = 0}) {
    final length = this.length;
    final sc = start.clamp(0, length);
    final truncated = length > sc + maxLength ? '${substring(sc, sc + maxLength - 1)}…' : this;

    return jsonEncode(truncated);
  }

  /// Only for debugging.
  /// Truncates a String in the middle with "…" if it's too long. Quotes and escapes the string.
  String truncateQuoteMiddle(final int maxLength, {final int start = 0}) {
    final length = this.length;
    final sc = start.clamp(0, length);
    final secondHalf = (maxLength - 1) ~/ 2;
    final firstHalf = maxLength - 1 - secondHalf;
    final truncated = length > sc + maxLength
        ? '${substring(sc, sc + firstHalf)}…${substring(length - secondHalf)}'
        : this;

    return jsonEncode(truncated);
  }

  Duration toDuration() => const Duration(seconds: 1) * double.parse(this);

  Locale toLocale({final String separator = '-'}) {
    final localeList = split(separator);
    switch (localeList.length) {
      case 2:
        return localeList.last.length == 4 // scriptCode length is 4
            ? Locale.fromSubtags(
                languageCode: localeList.first,
                scriptCode: localeList.last,
              )
            : Locale(localeList.first, localeList.last);
      case 3:
        return Locale.fromSubtags(
          languageCode: localeList.first,
          scriptCode: localeList[1],
          countryCode: localeList.last,
        );
      case 5:
        return Locale(localeList.first, localeList[1]);
      default:
        return Locale(localeList.first);
    }
  }

  /// Gets the path from Uri and adds a slash if it missing form the path.
  ///
  /// Returns `null` if path could be retrieved from uri.
  String? get path {
    final uriPath = Uri.tryParse(this)?.path;

    if (uriPath == null) {
      return null;
    }

    return uriPath.startsWith('/') ? uriPath : '/$uriPath';
  }
}
