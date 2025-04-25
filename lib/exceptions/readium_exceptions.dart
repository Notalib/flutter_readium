import 'package:flutter/services.dart';

class ReadiumException implements Exception {
  const ReadiumException(
    this.message, {
    this.type,
  });

  final String message;

  final Object? type;

  @override
  String toString() => 'ReadiumException{$message}';
}

class PublicationNotSetReadiumException extends ReadiumException {
  const PublicationNotSetReadiumException(super.message);

  @override
  String toString() => 'PublicationNotSetReadiumException{$message}';
}

class OfflineReadiumException extends ReadiumException {
  const OfflineReadiumException([
    final String? message,
  ]) : super('Offline: $message');

  @override
  String toString() => 'OfflineReadiumException';
}

// Order must match native code.
enum OpeningReadiumExceptionType {
  unsupportedFormat,
  notFound,
  parsingFailed,
  forbidden,
  unavailable,
  incorrectCredentials,
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
  ReadiumError(
    this.message, {
    this.code,
    this.data,
    final StackTrace? stackTrace,
  }) : stackTrace = stackTrace ?? StackTrace.current;

  final String message;
  final String? code;

  final Object? data;

  @override
  final StackTrace? stackTrace;

  @override
  bool operator ==(covariant final Object other) =>
      identical(this, other) ||
      other is ReadiumError && other.message == message && other.code == code;

  @override
  int get hashCode => message.hashCode ^ code.hashCode;

  @override
  String toString() =>
      'ReadiumError(message: $message, code: $code data: $data, stackTrace: $stackTrace)';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'message': message,
        if (code != null) 'code': code,
        if (data != null) 'data': data?.toString(),
        if (stackTrace != null) 'stackTrace': stackTrace?.toString(),
      };

  // ignore: sort_constructors_first
  factory ReadiumError.fromJson(final Map<String, dynamic> map) => ReadiumError(
        map['message'] as String,
        code: map['code'] != null ? map['code'] as String : null,
        data: map['data'] != null ? map['data'] as Object : null,
        stackTrace:
            map['stackTrace'] != null ? StackTrace.fromString(map['stackTrace'] as String) : null,
      );
}

class MaxRetryReadiumError extends ReadiumError {
  MaxRetryReadiumError({
    super.data,
  }) : super(
          'Max retry attempts to recover from error reached',
          code: '10001',
        );
}
