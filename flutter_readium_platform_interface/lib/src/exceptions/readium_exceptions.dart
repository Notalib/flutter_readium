import 'package:collection/collection.dart';
import 'package:flutter/services.dart';

import '../../flutter_readium_platform_interface.dart';

class ReadiumException implements Exception {
  const ReadiumException(this.message, {this.type});

  final String message;

  final Object? type;

  @override
  String toString() => 'ReadiumException{$message}';

  static ReadiumException fromPlatformException(PlatformException ex) {
    final type = OpeningReadiumExceptionType.values.firstWhereOrNull(
      (v) => v.name == ex.code,
    );
    // `ex.details` is `Object?` on the platform channel — for most error paths
    // it's a String, but the iOS HTTPError(.errorResponse) path puts the
    // response headers Map there. Prefer `ex.message` (always a human-readable
    // string from FlutterError on the native side), fall back to a stringified
    // details, then a generic 'unknown'. Avoids a Map-to-String cast crash.
    final message = ex.message ?? ex.details?.toString() ?? 'unknown';
    return ReadiumException(message, type: type);
  }

  static ReadiumException fromError(Object? err) {
    if (err is PlatformException) {
      return fromPlatformException(err);
    } else {
      return ReadiumException(err.toString(), type: err.runtimeType.toString());
    }
  }
}

class PublicationNotSetReadiumException extends ReadiumException {
  const PublicationNotSetReadiumException(super.message);

  @override
  String toString() => 'PublicationNotSetReadiumException{$message}';
}

class OfflineReadiumException extends ReadiumException {
  const OfflineReadiumException([final String? message]) : super('Offline: $message');

  @override
  String toString() => 'OfflineReadiumException';
}

// Matched by name against the native `code` string (see
// ReadiumException.fromPlatformException below), not by ordinal/position —
// neither iOS (FlutterError code: string literals) nor Android
// (PublicationError.ReadiumExceptionType.wireValue string constants) send an
// ordinal. Member order here is cosmetic.
enum OpeningReadiumExceptionType {
  formatNotSupported,
  readingError,
  notFound,
  forbidden,
  unavailable,
  incorrectCredentials,
  unknown,
}

class OpeningReadiumException extends ReadiumException {
  const OpeningReadiumException(super.message, {required super.type});

  @override
  String toString() => 'OpeningReadiumException{$type,$message}';
}

extension PlatformExceptionCodeExtension on PlatformException {
  int? get intCode => code.isEmpty ? null : int.tryParse(code, radix: 10);
}

class ReadiumError implements Error {
  factory ReadiumError.fromJson(final Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final message = jsonObject.optString('message', remove: true);
    final code = jsonObject.optNullableString('code', remove: true);
    final data = jsonObject.opt('data', remove: true);
    final stackTraceStr = jsonObject.optNullableString(
      'stackTrace',
      remove: true,
    );

    return ReadiumError(
      message,
      code: code,
      data: data,
      stackTrace: stackTraceStr != null ? StackTrace.fromString(stackTraceStr) : null,
    );
  }

  ReadiumError(
    this.message, {
    this.code,
    this.data,
    final StackTrace? stackTrace,
  }) : codeEnum = ReadiumErrorCode.fromWire(code),
       stackTrace = stackTrace ?? StackTrace.current;

  final String message;

  /// Raw wire code as sent by the native side. Kept for backwards
  /// compatibility and debugging; prefer [codeEnum] for typed handling.
  final String? code;

  /// Typed classification of [code], parsed once at construction time.
  /// Falls back to [ReadiumErrorCode.unknown] for unrecognised or missing
  /// codes — never throws.
  final ReadiumErrorCode codeEnum;

  final Object? data;

  @override
  final StackTrace? stackTrace;

  @override
  bool operator ==(covariant final Object other) =>
      identical(this, other) || other is ReadiumError && other.message == message && other.code == code;

  @override
  int get hashCode => message.hashCode ^ code.hashCode;

  @override
  String toString() => 'ReadiumError(message: $message, code: $code data: $data, stackTrace: $stackTrace)';

  Map<String, dynamic> toJson() => {}
    ..put('message', message)
    ..putOpt('code', code)
    ..putOpt('data', data?.toString())
    ..putOpt('stackTrace', stackTrace?.toString());
}
