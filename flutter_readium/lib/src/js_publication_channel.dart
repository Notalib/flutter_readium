import 'dart:js_interop';
import 'dart:js_interop_unsafe';
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
  external void setAudioRecoveryPolicy(JSString policyJson);
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

  static void setAudioRecoveryPolicy(String policyJson) {
    _readiumReader.setAudioRecoveryPolicy(policyJson.toJS);
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
      throw _platformExceptionForJsError(jsError, stackTrace);
    }
  }

  Future<String> getPublication(String link) async {
    try {
      final publicationPromise = _readiumReader.getPublication(link.toJS);
      final publicationString = (await publicationPromise.toDart).toDart;

      return publicationString;
    } on Object catch (jsError, stackTrace) {
      throw _platformExceptionForJsError(jsError, stackTrace);
    }
  }

  static int? _extractStatusCode(String errorMessage) {
    final regex = RegExp(r'HTTP status code (\d{3})');
    final match = regex.firstMatch(errorMessage);
    return match != null ? int.parse(match.group(1)!) : null;
  }

  static String _convertToNativeCode(int? statusCode, String errorMessage) {
    final lowerMessage = errorMessage.toLowerCase();
    if (lowerMessage.contains('scheme not supported')) {
      return ReadiumErrorCode.unsupportedScheme.name;
    }
    if (lowerMessage.contains('timed out preparing audio playback')) {
      return ReadiumErrorCode.audioStreamNetworkError.name;
    }
    switch (statusCode) {
      case 415:
        return ReadiumErrorCode.formatNotSupported.name;
      case 404:
        return ReadiumErrorCode.notFound.name;
      case 400:
        return ReadiumErrorCode.readingError.name;
      case 403:
        return ReadiumErrorCode.forbidden.name;
      case 500:
        return ReadiumErrorCode.unavailable.name;
      case 401:
        return ReadiumErrorCode.incorrectCredentials.name;
      default:
        return ReadiumErrorCode.unknown.name;
    }
  }

  /// Reads a typed `code` (and optional `details`) directly off a JS error
  /// object, as emitted by the web bundle's `ReadiumWebError`
  /// (`web/src/errors/ReadiumWebError.ts`). Returns `null` for untyped
  /// throws (e.g. raw upstream/toolkit errors), so callers can fall back to
  /// the string-matching heuristics below.
  static ({String code, Map<String, Object?> details})? _extractTypedJsError(Object jsError) {
    try {
      final jsObj = jsError as JSObject;
      final codeAny = jsObj.getProperty<JSAny?>('code'.toJS);
      final code = (codeAny as JSString?)?.toDart;
      if (code == null || code.isEmpty) return null;

      final details = <String, Object?>{};
      final detailsAny = jsObj.getProperty<JSAny?>('details'.toJS);
      final dartifiedDetails = detailsAny?.dartify();
      if (dartifiedDetails is Map) {
        for (final entry in dartifiedDetails.entries) {
          details[entry.key.toString()] = entry.value;
        }
      }
      return (code: code, details: details);
    } on Object {
      return null;
    }
  }

  static PlatformException _platformExceptionForJsError(
    Object jsError,
    StackTrace stackTrace,
  ) {
    final errorString = describeJsError(jsError);
    final typed = _extractTypedJsError(jsError);
    if (typed != null) {
      return PlatformException(
        code: typed.code,
        message: errorString,
        details: {'message': errorString, ...typed.details},
        stacktrace: stackTrace.toString(),
      );
    }

    final statusCode = _extractStatusCode(errorString);
    final nativeCode = _convertToNativeCode(statusCode, errorString);
    final details = <String, Object?>{'message': errorString};
    if (statusCode != null) {
      details['httpStatus'] = statusCode;
    }

    return PlatformException(
      code: nativeCode,
      message: errorString,
      details: details,
      stacktrace: stackTrace.toString(),
    );
  }

  /// Runs a synchronous call into the JS bundle, converting any thrown JS
  /// error into a [PlatformException] via [_platformExceptionForJsError] so
  /// it isn't leaked to callers unconverted.
  static T _guardJsCall<T>(T Function() call) {
    try {
      return call();
    } on Object catch (jsError, stackTrace) {
      throw _platformExceptionForJsError(jsError, stackTrace);
    }
  }

  static Future<void> goToLocator(String locatorJson) async {
    try {
      await _readiumReader.goTo(locatorJson.toJS).toDart;
    } on Object catch (jsError, stackTrace) {
      throw _platformExceptionForJsError(jsError, stackTrace);
    }
  }

  static void goBackward() {
    _guardJsCall(() => _readiumReader.goBackward());
  }

  static void goForward() {
    _guardJsCall(() => _readiumReader.goForward());
  }

  void closePublication() {
    try {
      _readiumReader.closePublication();
    } on Object catch (error) {
      _log.e('Error closing publication: $error');
    }
  }

  static void playAudio({String? locatorJson}) {
    _guardJsCall(() => _readiumReader.play(locatorJson?.toJS));
  }

  static void pauseAudio() {
    _guardJsCall(() => _readiumReader.pause());
  }

  static void resumeAudio() {
    _guardJsCall(() => _readiumReader.resume());
  }

  static void stopAudio() {
    _guardJsCall(() => _readiumReader.stop());
  }

  static void nextAudio() {
    _guardJsCall(() => _readiumReader.next());
  }

  static void previousAudio() {
    _guardJsCall(() => _readiumReader.previous());
  }

  static void seekBy(double seconds) {
    _guardJsCall(() => _readiumReader.seekBy(seconds.toJS));
  }

  static bool goToProgression(double progression) =>
      _guardJsCall(() => _readiumReader.goToProgression(progression.toJS).toDart);

  static void setNarrationSyncEnabled(bool enabled) {
    _guardJsCall(() => _readiumReader.setNarrationSyncEnabled(enabled.toJS));
  }

  static void setAudioPreferences(String preferencesJson) {
    _guardJsCall(() => _readiumReader.setAudioPreferences(preferencesJson.toJS));
  }

  static Future<String> ttsGetAvailableVoices() async {
    try {
      return (await _readiumReader.ttsGetAvailableVoices().toDart).toDart;
    } on Object catch (jsError, stackTrace) {
      throw _platformExceptionForJsError(jsError, stackTrace);
    }
  }

  static Future<void> ttsEnable(
    String prefsJson, {
    String? fromLocatorJson,
  }) async {
    try {
      await _readiumReader.ttsEnable(prefsJson.toJS, fromLocatorJson?.toJS).toDart;
    } on Object catch (jsError, stackTrace) {
      throw _platformExceptionForJsError(jsError, stackTrace);
    }
  }

  static void ttsSetVoice(String identifier, {String? lang}) {
    _guardJsCall(() => _readiumReader.ttsSetVoice(identifier.toJS, lang?.toJS));
  }

  static void ttsSetPreferences(String prefsJson) {
    _guardJsCall(() => _readiumReader.ttsSetPreferences(prefsJson.toJS));
  }

  static Future<void> audioEnable(
    String prefsJson, {
    String? fromLocatorJson,
  }) async {
    try {
      await _readiumReader.audioEnable(prefsJson.toJS, fromLocatorJson?.toJS).toDart;
    } on Object catch (jsError, stackTrace) {
      throw _platformExceptionForJsError(jsError, stackTrace);
    }
  }

  static Future<String> getResourceUrl(String href) async {
    try {
      return (await _readiumReader.getResourceUrl(href.toJS).toDart).toDart;
    } on Object catch (jsError, stackTrace) {
      // TS now throws typed ReadiumWebErrors (NoPublication / InvalidArgument /
      // ResourceReadError depending on which guard failed) — read the code
      // instead of hardcoding ResourceReadError for every failure.
      throw _platformExceptionForJsError(jsError, stackTrace);
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
      throw _platformExceptionForJsError(jsError, stackTrace);
    }
  }

  void applyDecorations(String group, String decorationsJson) {
    final isReady = _readiumReader.isNavigatorReady.toDart;
    if (isReady) {
      _guardJsCall(() => _readiumReader.applyDecorations(group.toJS, decorationsJson.toJS));
    } else {
      ReadiumLog.w('ReadiumReader is not ready yet, skipping applyDecorations');
    }
  }

  void setDecorationStyle(String? utteranceStyleJson, String? rangeStyleJson) {
    _guardJsCall(
      () => _readiumReader.setDecorationStyle(
        utteranceStyleJson?.toJS,
        rangeStyleJson?.toJS,
      ),
    );
  }
}
