import 'dart:js_interop';
import 'package:flutter/services.dart';

@JS('ReadiumReader')
extension type ReadiumReader._(JSObject _) implements JSObject {
  external ReadiumReader();
  external JSPromise openPublication(
      JSString publicationURL, JSBoolean? isAudiobook, JSBoolean? hasText, JSString? initialPositionJson);
  external JSPromise getPublication(JSString link);
  external JSPromise goTo(JSString location);
  external void goLeft();
  external void goRight();
  external void closePublication();
  external JSPromise getResource(JSString linkString, JSBoolean? asBytes);
}

@JS()
external set updateLocator(JSFunction f);

class JsPublicationChannel {
  static final ReadiumReader _readiumReader = ReadiumReader();

  Future<void> openPublication(String publicationURL,
      {bool? isAudiobook = false, bool? hasText = false, String? initialPositionJson}) async {
    try {
      await _readiumReader
          .openPublication(publicationURL.toJS, isAudiobook?.toJS, hasText?.toJS, initialPositionJson?.toJS)
          .toDart;
    } on Object catch (jsError, stackTrace) {
      String errorString = jsError.toString();
      int? statusCode = _extractStatusCode(errorString);
      String nativeCode = _convertToNativeCode(statusCode);
      throw PlatformException(
        code: nativeCode,
        message: errorString,
        details: statusCode,
        stacktrace: stackTrace.toString(),
      );
    }
  }

  Future<String> getPublication(String link) async {
    try {
      final publicationPromise = _readiumReader.getPublication(link.toJS);
      final publicationString = await publicationPromise.toDart as String;

      return publicationString;
    } on Object catch (jsError, stackTrace) {
      String errorString = jsError.toString();
      int? statusCode = _extractStatusCode(errorString);
      String nativeCode = _convertToNativeCode(statusCode);

      throw PlatformException(
        code: nativeCode,
        message: errorString,
        details: statusCode,
        stacktrace: stackTrace.toString(),
      );
    }
  }

  static int? _extractStatusCode(String errorMessage) {
    final regex = RegExp(r'HTTP status code (\d{3})');
    final match = regex.firstMatch(errorMessage);
    return match != null ? int.parse(match.group(1)!) : null;
  }

  static String _convertToNativeCode(int? statusCode) {
    switch (statusCode) {
      case 415:
        return '0';
      case 404:
        return '1';
      case 400:
        return '2';
      case 403:
        return '3';
      case 500:
        return '4';
      case 401:
        return '5';
      default:
        return '';
    }
  }

  static Future<void> goToLocation(String locationHref) async {
    try {
      await _readiumReader.goTo(locationHref.toJS).toDart;
    } on Object catch (jsError, stackTrace) {
      String errorString = jsError.toString();
      int? statusCode = _extractStatusCode(errorString);
      String nativeCode = _convertToNativeCode(statusCode);

      throw PlatformException(
        code: nativeCode,
        message: errorString,
        details: statusCode,
        stacktrace: stackTrace.toString(),
      );
    }
  }

  static void goLeft() {
    _readiumReader.goLeft();
  }

  static void goRight() {
    _readiumReader.goRight();
  }

  void closePublication() {
    _readiumReader.closePublication();
  }

  Future<String> getResource(String link, {bool? asBytes}) async {
    try {
      final resourceJS = _readiumReader.getResource(link.toJS, asBytes?.toJS);
      var resourceString = await resourceJS.toDart as String;
      return resourceString;
    } on Object catch (jsError, stackTrace) {
      String errorString = jsError.toString();
      int? statusCode = _extractStatusCode(errorString);
      String nativeCode = _convertToNativeCode(statusCode);

      throw PlatformException(
        code: nativeCode,
        message: errorString,
        details: statusCode,
        stacktrace: stackTrace.toString(),
      );
    }
  }
}
