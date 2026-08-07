import 'package:collection/collection.dart';
import 'package:flutter/services.dart';

import '../../flutter_readium_platform_interface.dart';

class ReadiumException implements Exception {
  ReadiumException(this.error);

  final ReadiumError error;

  String get message => error.message;

  String? get code => error.code;

  ReadiumErrorCode get codeEnum => error.codeEnum;

  Map<String, dynamic>? get details => error.details;

  String? get href => error.href;

  int? get attempt => error.attempt;

  int? get maxAttempts => error.maxAttempts;

  int? get httpStatus => error.httpStatus;

  bool get isFatal => error.isFatal;

  bool get isInformational => error.isInformational;

  @override
  String toString() => 'ReadiumException{code: $code, message: $message, details: $details}';

  static ReadiumException fromPlatformException(PlatformException ex) =>
      ReadiumException(ReadiumError.fromPlatformException(ex));

  static ReadiumException fromError(Object? err) {
    if (err is PlatformException) {
      return fromPlatformException(err);
    }
    if (err is ReadiumError) return ReadiumException(err);
    if (err is ReadiumException) return err;
    return ReadiumException(ReadiumError(err?.toString() ?? 'unknown'));
  }
}

class ReadiumError {
  factory ReadiumError.fromJson(final Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final message = jsonObject.optString('message', remove: true);
    final code = jsonObject.optNullableString('code', remove: true);
    final rawData = jsonObject.opt('data', remove: true);
    jsonObject.remove('stackTrace');

    return ReadiumError(
      message,
      code: code,
      details: _detailsFromWire(rawData),
    );
  }

  factory ReadiumError.fromPlatformException(PlatformException ex) {
    final details = _detailsFromWire(ex.details);
    final detailMessage = details?.optNullableString('message');
    final message = ex.message ?? detailMessage ?? ex.details?.toString() ?? 'unknown';
    final code = ex.code.isEmpty ? null : ex.code;

    return ReadiumError(message, code: code, details: details);
  }

  ReadiumError(
    this.message, {
    this.code,
    Map<String, dynamic>? details,
  }) : details = details == null ? null : Map.unmodifiable(details),
       codeEnum = ReadiumErrorCode.fromWire(code);

  static const _detailsEquality = DeepCollectionEquality();

  /// Tolerates a stale native side still sending `data` as a freeform
  /// string (pre-R2 wire format) by wrapping it as `{"message": <string>}`,
  /// so the stream decoder never crashes on a legacy payload.
  ///
  /// The constructor makes the result unmodifiable, so this only needs to
  /// return a plain map.
  static Map<String, dynamic>? _detailsFromWire(Object? rawData) {
    if (rawData == null) return null;
    if (rawData is Map<String, dynamic>) return rawData;
    if (rawData is Map) return Map<String, dynamic>.from(rawData);
    return {'message': rawData.toString()};
  }

  final String message;

  /// Raw wire code as sent by the native side. Kept for backwards
  /// compatibility and debugging; prefer [codeEnum] for typed handling.
  final String? code;

  /// Typed classification of [code], parsed once at construction time.
  /// Falls back to [ReadiumErrorCode.unknown] for unrecognised or missing
  /// codes — never throws.
  final ReadiumErrorCode codeEnum;

  /// Mirrors [ReadiumErrorCode.isFatal] for convenience when handling stream
  /// events or exception payloads directly.
  bool get isFatal => codeEnum.isFatal;

  /// Mirrors [ReadiumErrorCode.isInformational] for convenience when handling
  /// stream events or exception payloads directly.
  bool get isInformational => codeEnum.isInformational;

  /// Structured supplementary payload. All fields are optional and producer
  /// specific — see `docs/api-reference/error-codes.md`. Prefer the typed
  /// getters ([href], [attempt], [maxAttempts], [httpStatus]) over reading
  /// this map directly.
  ///
  /// Unmodifiable: the constructor copies the caller's map so post-construction
  /// mutation can't silently break `==`/`hashCode`, which are computed over it.
  final Map<String, dynamic>? details;

  /// The resource href the error relates to, if any (e.g. the audio
  /// resource being streamed).
  String? get href => details?.optNullableString('href');

  /// The current retry attempt number, for informational recovery events
  /// (e.g. `audioStreamRetry`).
  int? get attempt => details?.optNullableInt('attempt');

  /// The maximum number of retry attempts, for informational recovery
  /// events (e.g. `audioStreamRetry`).
  int? get maxAttempts => details?.optNullableInt('maxAttempts');

  /// The HTTP status code that triggered the error, when known.
  int? get httpStatus => details?.optNullableInt('httpStatus');

  @override
  bool operator ==(covariant final Object other) =>
      identical(this, other) ||
      other is ReadiumError &&
          other.message == message &&
          other.code == code &&
          _detailsEquality.equals(other.details, details);

  @override
  int get hashCode => Object.hash(message, code, _detailsEquality.hash(details));

  @override
  String toString() => 'ReadiumError(message: $message, code: $code, details: $details)';

  Map<String, dynamic> toJson() => {}
    ..put('message', message)
    ..putOpt('code', code)
    ..putObjectIfNotEmpty('data', details);
}
