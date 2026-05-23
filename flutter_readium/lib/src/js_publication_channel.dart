import 'dart:js_interop';
import 'package:flutter/services.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';

@JS('ReadiumReader')
extension type ReadiumReader._(JSObject _) implements JSObject {
  external ReadiumReader();
  external JSPromise openPublication(
    JSString publicationURL,
    JSString pubId,
    JSString? initialPositionJson,
    JSString preferencesJson,
  );
  external JSPromise<JSString> getPublication(JSString link);
  external JSPromise goTo(JSString location);
  external void goBackward();
  external void goForward();
  external void closePublication();
  external JSPromise<JSString> getResource(JSString linkString, JSBoolean? asBytes);
  external void setEPUBPreferences(JSString newPreferencesString);
  external JSBoolean get isNavigatorReady;
  external void play(JSString? locatorJson);
  external void pause();
  external void resume();
  external void stop();
  external void next();
  external void previous();
  external void seekBy(JSNumber seconds);
  external JSBoolean goToProgression(JSNumber progression);
  external void setAudioPreferences(JSString preferencesJson);
  external JSPromise<JSString> ttsGetAvailableVoices();
  external JSPromise<JSAny?> ttsEnable(JSString prefsJson, JSString? fromLocatorJson);
  external void ttsSetVoice(JSString identifier, JSString? lang);
  external void ttsSetPreferences(JSString prefsJson);
  external JSPromise<JSAny?> audioEnable(JSString prefsJson, JSString? fromLocatorJson);
}

@JS()
external set updateTextLocator(JSFunction f);

@JS()
external set updateTimebasedPlayerState(JSFunction f);

@JS()
external set updateReaderStatus(JSFunction f);

@JS()
external set onTextSelectedCallback(JSFunction f);

@JS()
external set onSelectionActionCallback(JSFunction f);

@JS()
external set onDecorationInteractionCallback(JSFunction f);

class JsPublicationChannel {
  static final ReadiumReader _readiumReader = ReadiumReader();

  Future<void> openPublication(
    String publicationURL, {
    required String pubId,
    required String initialPreferences,
    String? initialPositionJson,
  }) async {
    try {
      await _readiumReader
          .openPublication(publicationURL.toJS, pubId.toJS, initialPositionJson?.toJS, initialPreferences.toJS)
          .toDart;
    } on Object catch (jsError, stackTrace) {
      final errorString = jsError.toString();
      final statusCode = _extractStatusCode(errorString);
      final nativeCode = _convertToNativeCode(statusCode);
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
      final publicationString = (await publicationPromise.toDart).toDart;

      return publicationString;
    } on Object catch (jsError, stackTrace) {
      final errorString = jsError.toString();
      final statusCode = _extractStatusCode(errorString);
      final nativeCode = _convertToNativeCode(statusCode);

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
      final errorString = jsError.toString();
      final statusCode = _extractStatusCode(errorString);
      final nativeCode = _convertToNativeCode(statusCode);

      throw PlatformException(
        code: nativeCode,
        message: errorString,
        details: statusCode,
        stacktrace: stackTrace.toString(),
      );
    }
  }

  static void goBackward() {
    _readiumReader.goBackward();
  }

  static void goForward() {
    _readiumReader.goForward();
  }

  void closePublication() {
    _readiumReader.closePublication();
  }

  Future<String> getResource(String link, {bool? asBytes}) async {
    try {
      final resourceJS = _readiumReader.getResource(link.toJS, asBytes?.toJS);
      final resourceString = (await resourceJS.toDart).toDart;
      return resourceString;
    } on Object catch (jsError, stackTrace) {
      final errorString = jsError.toString();
      final statusCode = _extractStatusCode(errorString);
      final nativeCode = _convertToNativeCode(statusCode);

      throw PlatformException(
        code: nativeCode,
        message: errorString,
        details: statusCode,
        stacktrace: stackTrace.toString(),
      );
    }
  }

  static void playAudio({String? locatorJson}) {
    _readiumReader.play(locatorJson?.toJS);
  }

  static void pauseAudio() {
    _readiumReader.pause();
  }

  static void resumeAudio() {
    _readiumReader.resume();
  }

  static void stopAudio() {
    _readiumReader.stop();
  }

  static void nextAudio() {
    _readiumReader.next();
  }

  static void previousAudio() {
    _readiumReader.previous();
  }

  static void seekBy(double seconds) {
    _readiumReader.seekBy(seconds.toJS);
  }

  static bool goToProgression(double progression) => _readiumReader.goToProgression(progression.toJS).toDart;

  static void setAudioPreferences(String preferencesJson) {
    _readiumReader.setAudioPreferences(preferencesJson.toJS);
  }

  static Future<String> ttsGetAvailableVoices() async => (await _readiumReader.ttsGetAvailableVoices().toDart).toDart;

  static Future<void> ttsEnable(String prefsJson, {String? fromLocatorJson}) async {
    await _readiumReader.ttsEnable(prefsJson.toJS, fromLocatorJson?.toJS).toDart;
  }

  static void ttsSetVoice(String identifier, {String? lang}) {
    _readiumReader.ttsSetVoice(identifier.toJS, lang?.toJS);
  }

  static void ttsSetPreferences(String prefsJson) {
    _readiumReader.ttsSetPreferences(prefsJson.toJS);
  }

  static Future<void> audioEnable(String prefsJson, {String? fromLocatorJson}) async {
    await _readiumReader.audioEnable(prefsJson.toJS, fromLocatorJson?.toJS).toDart;
  }

  Future<void> setEPUBPreferences(String newPreferencesString) async {
    try {
      final isReady = _readiumReader.isNavigatorReady.toDart;
      if (isReady) {
        _readiumReader.setEPUBPreferences(newPreferencesString.toJS);
      } else {
        ReadiumLog.w('ReadiumReader is not ready yet, skipping setEPUBPreferences');
      }
    } on Object catch (jsError, stackTrace) {
      final errorString = jsError.toString();
      final statusCode = _extractStatusCode(errorString);
      final nativeCode = _convertToNativeCode(statusCode);

      throw PlatformException(
        code: nativeCode,
        message: errorString,
        details: statusCode,
        stacktrace: stackTrace.toString(),
      );
    }
  }
}
