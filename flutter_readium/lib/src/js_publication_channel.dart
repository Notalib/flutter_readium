import 'dart:js_interop';
import 'package:flutter/services.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'js_error.dart';

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
  external JSPromise goTo(JSString locatorJson);
  external void goBackward();
  external void goForward();
  external void closePublication();
  external void setEPUBPreferences(JSString newPreferencesString);
  external void setLogLevel(JSNumber level);
  external void applyDecorations(JSString group, JSString decorationsJson);
  external void setDecorationStyle(
    JSString? utteranceStyleJson,
    JSString? rangeStyleJson,
  );
  external JSBoolean get isNavigatorReady;
  external void play(JSString? locatorJson);
  external void pause();
  external void resume();
  external void stop();
  external void next();
  external void previous();
  external void seekBy(JSNumber seconds);
  external JSBoolean goToProgression(JSNumber progression);
  external void setNarrationSyncEnabled(JSBoolean enabled);
  external void setAudioPreferences(JSString preferencesJson);
  external JSPromise<JSString> ttsGetAvailableVoices();
  external JSPromise<JSAny?> ttsEnable(
    JSString prefsJson,
    JSString? fromLocatorJson,
  );
  external void ttsSetVoice(JSString identifier, JSString? lang);
  external void ttsSetPreferences(JSString prefsJson);
  external JSPromise<JSAny?> audioEnable(
    JSString prefsJson,
    JSString? fromLocatorJson,
  );
  external JSPromise<JSString> getResourceUrl(JSString href);
}

@JS()
external set updateTextLocator(JSFunction f);

@JS()
external set updateNarrationSync(JSFunction f);

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

@JS()
external set onErrorCallback(JSFunction f);

@JS()
external set onImageTappedCallback(JSFunction f);

class JsPublicationChannel {
  static final ReadiumReader _readiumReader = ReadiumReader();
  static final _log = ReadiumLog.tag('JsChannel');

  static void setLogLevel(LogLevel level) {
    _readiumReader.setLogLevel(level.index.toJS);
  }

  Future<void> openPublication(
    String publicationURL, {
    required String pubId,
    required String initialPreferences,
    String? initialPositionJson,
  }) async {
    try {
      await _readiumReader
          .openPublication(
            publicationURL.toJS,
            pubId.toJS,
            initialPositionJson?.toJS,
            initialPreferences.toJS,
          )
          .toDart;
    } on Object catch (jsError, stackTrace) {
      final errorString = describeJsError(jsError);
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
      final errorString = describeJsError(jsError);
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

  static Future<void> goToLocator(String locatorJson) async {
    try {
      await _readiumReader.goTo(locatorJson.toJS).toDart;
    } on Object catch (jsError, stackTrace) {
      final errorString = describeJsError(jsError);
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
    try {
      _readiumReader.closePublication();
    } on Object catch (error) {
      _log.e('Error closing publication: $error');
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

  static void setNarrationSyncEnabled(bool enabled) {
    _readiumReader.setNarrationSyncEnabled(enabled.toJS);
  }

  static void setAudioPreferences(String preferencesJson) {
    _readiumReader.setAudioPreferences(preferencesJson.toJS);
  }

  static Future<String> ttsGetAvailableVoices() async {
    try {
      return (await _readiumReader.ttsGetAvailableVoices().toDart).toDart;
    } on Object catch (jsError, stackTrace) {
      final errorString = describeJsError(jsError);
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

  static Future<void> ttsEnable(
    String prefsJson, {
    String? fromLocatorJson,
  }) async {
    try {
      await _readiumReader.ttsEnable(prefsJson.toJS, fromLocatorJson?.toJS).toDart;
    } on Object catch (jsError, stackTrace) {
      final errorString = describeJsError(jsError);
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

  static void ttsSetVoice(String identifier, {String? lang}) {
    _readiumReader.ttsSetVoice(identifier.toJS, lang?.toJS);
  }

  static void ttsSetPreferences(String prefsJson) {
    _readiumReader.ttsSetPreferences(prefsJson.toJS);
  }

  static Future<void> audioEnable(
    String prefsJson, {
    String? fromLocatorJson,
  }) async {
    try {
      await _readiumReader.audioEnable(prefsJson.toJS, fromLocatorJson?.toJS).toDart;
    } on Object catch (jsError, stackTrace) {
      final errorString = describeJsError(jsError);
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

  static Future<String> getResourceUrl(String href) async {
    try {
      return (await _readiumReader.getResourceUrl(href.toJS).toDart).toDart;
    } on Object catch (jsError, stackTrace) {
      final errorString = describeJsError(jsError);
      throw PlatformException(
        code: 'ResourceReadError',
        message: errorString,
        stacktrace: stackTrace.toString(),
      );
    }
  }

  Future<void> setEPUBPreferences(String newPreferencesString) async {
    try {
      final isReady = _readiumReader.isNavigatorReady.toDart;
      if (isReady) {
        _readiumReader.setEPUBPreferences(newPreferencesString.toJS);
      } else {
        _log.w('ReadiumReader is not ready yet, skipping setEPUBPreferences');
      }
    } on Object catch (jsError, stackTrace) {
      final errorString = describeJsError(jsError);
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

  void applyDecorations(String group, String decorationsJson) {
    final isReady = _readiumReader.isNavigatorReady.toDart;
    if (isReady) {
      _readiumReader.applyDecorations(group.toJS, decorationsJson.toJS);
    } else {
      ReadiumLog.w('ReadiumReader is not ready yet, skipping applyDecorations');
    }
  }

  void setDecorationStyle(String? utteranceStyleJson, String? rangeStyleJson) {
    _readiumReader.setDecorationStyle(
      utteranceStyleJson?.toJS,
      rangeStyleJson?.toJS,
    );
  }
}
