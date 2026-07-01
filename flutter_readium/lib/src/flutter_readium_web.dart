import 'dart:async';
import 'dart:convert';
import 'dart:js_interop' as js_interop;

import 'package:flutter/services.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'js_publication_channel.dart';

/// Provides JS-callable callbacks for pure audiobooks, where [ReadiumWebView]
/// (and its [registerJSExports] call) is never in the widget tree.
@js_interop.JSExport()
class _AudiobookCallbacks {
  static final _log = ReadiumLog.tag('WebPlugin');

  @js_interop.JSExport()
  void onTimebasedPlayerState(final String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final state = ReadiumTimebasedState.fromJson(json);
    FlutterReadiumWebPlugin.addTimeBasedStateUpdate(state);
  }

  @js_interop.JSExport()
  void onReaderStatus(final String statusString) {
    final status = ReadiumReaderStatus.optFromString(statusString);
    if (status != null) {
      FlutterReadiumWebPlugin.addReaderStatusUpdate(status);
    } else {
      _log.w('Unknown ReadiumReaderStatus: $statusString');
    }
  }

  @js_interop.JSExport()
  void onErrorHandler(final String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final error = ReadiumError.fromJson(json);
    FlutterReadiumWebPlugin.addErrorEvent(error);
  }
}

class FlutterReadiumWebPlugin extends FlutterReadiumPlatform {
  static final _log = ReadiumLog.tag('WebPlugin');

  static void registerWith(Registrar registrar) {
    FlutterReadiumPlatform.instance = FlutterReadiumWebPlugin();
  }

  static _AudiobookCallbacks? _audiobookCallbacks;

  static final StreamController<Locator> _locatorTextController = StreamController<Locator>.broadcast();
  static final StreamController<ReadiumTimebasedState> _timebasedStateController =
      StreamController<ReadiumTimebasedState>.broadcast();
  static final StreamController<ReadiumReaderStatus> _readerStatusController =
      StreamController<ReadiumReaderStatus>.broadcast();
  static final StreamController<ReadiumError> _errorEventController = StreamController<ReadiumError>.broadcast();
  static final StreamController<bool> _narrationSyncController = StreamController<bool>.broadcast();

  static void addTextLocatorUpdate(Locator locator) {
    _locatorTextController.add(locator);
  }

  static void addNarrationSyncUpdate(bool synced) {
    _narrationSyncController.add(synced);
  }

  static void addTimeBasedStateUpdate(ReadiumTimebasedState timebasedState) {
    _timebasedStateController.add(timebasedState);
  }

  static void addReaderStatusUpdate(ReadiumReaderStatus status) {
    _readerStatusController.add(status);
  }

  static void addErrorEvent(ReadiumError error) {
    _errorEventController.add(error);
  }

  @override
  Stream<Locator> get onTextLocatorChanged => _locatorTextController.stream;

  @override
  Stream<bool> get onNarrationSyncChanged => _narrationSyncController.stream;

  @override
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged => _timebasedStateController.stream;

  @override
  Stream<ReadiumReaderStatus> get onReaderStatusChanged => _readerStatusController.stream;

  @override
  Future<void> setLogLevel(LogLevel level) async {
    ReadiumLog.setLevel(level);
    // Forward to the JS bundle so web-side logging respects the same level.
    JsPublicationChannel.setLogLevel(level);
  }

  @override
  Future<void> setCustomHeaders(Map<String, String> headers) async {
    _log.w(
      'setCustomHeaders is not supported on web (browser controls HTTP headers)',
    );
  }

  @override
  void setDefaultPreferences(EPUBPreferences preferences) {
    defaultPreferences = preferences;
  }

  @override
  Future<Publication> loadPublication(String pubUrl) async {
    Publication? publication;

    try {
      final publicationString = await JsPublicationChannel().getPublication(
        pubUrl,
      );

      var publicationJson = jsonDecode(publicationString) as Map<String, dynamic>;

      publicationJson = _transformPublicationJson(publicationJson);

      publication = Publication.fromJson(publicationJson);
      if (publication == null) {
        throw ReadiumError('Failed to parse Publication JSON');
      }
    } on PlatformException catch (e) {
      final type = e.intCode;
      throw OpeningReadiumException(
        '${e.code}: ${e.message ?? 'Unknown `PlatformException`'}',
        type: type == null ? null : OpeningReadiumExceptionType.values[type],
      );
    } on Error catch (e) {
      final eString = e.toString();
      throw ReadiumError('Error in PublicationChannel web: $eString');
    } on Exception catch (e) {
      final eString = e.toString();
      throw ReadiumError('Exception in PublicationChannel web: $eString');
    }

    return publication;
  }

  static Map<String, dynamic> _transformPublicationJson(
    final Map<String, dynamic> publicationJson,
  ) {
    // The upstream ts-toolkit's Manifest.serialize() already produces correct
    // RWPM JSON (flat arrays for links/readingOrder/resources/toc, proper
    // metadata keys, LocalizedString as {lang: value} maps). The only known
    // issue is that raw manifest data passing through `otherMetadata` may carry
    // the literal key "undefined" instead of the BCP-47 "und" for the undefined
    // language. Fix that recursively.
    _replaceUndefinedKey(publicationJson);

    // Handle sortAs edge case: upstream serializes as a LocalizedString map
    // but Dart Publication.fromJson expects a plain String.
    if (publicationJson.containsKey('metadata') && publicationJson['metadata'] is Map) {
      final metadataMap = publicationJson['metadata'] as Map<String, dynamic>;

      if (metadataMap.containsKey('sortAs')) {
        final sortAs = metadataMap['sortAs'];
        if (sortAs is Map) {
          if (sortAs.isNotEmpty) {
            metadataMap['sortAs'] = sortAs.values.first;
          } else {
            metadataMap['sortAs'] = null;
          }
        } else if (sortAs != null && sortAs is! String) {
          metadataMap['sortAs'] = null;
        }
      }
    }

    return publicationJson;
  }

  /// Recursively replaces the literal key `"undefined"` with `"und"` (the
  /// BCP-47 tag for undetermined language) throughout a JSON structure.
  static void _replaceUndefinedKey(Map<dynamic, dynamic> map) {
    final keysToReplace = <dynamic>[];
    map.forEach((key, value) {
      if (key == 'undefined') {
        keysToReplace.add(key);
      }
      if (value is Map) {
        _replaceUndefinedKey(value);
      } else if (value is List) {
        for (final item in value) {
          if (item is Map) {
            _replaceUndefinedKey(item);
          }
        }
      }
    });
    for (final key in keysToReplace) {
      map['und'] = map.remove(key);
    }
  }

  @override
  Future<Publication> openPublication(String pubUrl) async {
    final publication = await loadPublication(pubUrl);

    if (publication.conformsToReadiumAudiobook) {
      // Pure audiobooks: ReadiumWebView (and its #container div) is not in the
      // widget tree, so call openPublication on the JS side directly.
      // AudioNavigator drives <audio> elements and needs no DOM container.
      // Sync-narration EPUBs (containsMediaOverlays) DO need the container —
      // those publications use the EPUB navigator and are handled by ReadiumWebView.
      //
      // Register the JS->Dart callbacks that ReadiumWebViewState would normally
      // set up, since there is no ReadiumWebView in the tree for audiobooks.
      // Hold a static reference so Dart's GC doesn't collect the instance while
      // the JS AudioNavigator still holds the function references.
      _audiobookCallbacks = _AudiobookCallbacks();
      updateTimebasedPlayerState = _audiobookCallbacks!.onTimebasedPlayerState.toJS;
      updateReaderStatus = _audiobookCallbacks!.onReaderStatus.toJS;
      onErrorCallback = _audiobookCallbacks!.onErrorHandler.toJS;
      try {
        await JsPublicationChannel().openPublication(
          pubUrl,
          pubId: publication.identifier,
          initialPreferences: json.encode(
            defaultPreferences?.toJson() ?? <String, dynamic>{},
          ),
        );
      } on Exception catch (e) {
        throw ReadiumError('Exception opening audiobook on web: $e');
      }
    }

    return publication;
  }

  @override
  Future<void> closePublication() async {
    JsPublicationChannel().closePublication();
    _audiobookCallbacks = null;
  }

  @override
  Future<void> goBackward({final bool animated = true}) async {
    JsPublicationChannel.goBackward();
  }

  @override
  Future<void> goForward({final bool animated = true}) async {
    JsPublicationChannel.goForward();
  }

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    defaultPreferences = preferences;
    JsPublicationChannel().setEPUBPreferences(
      json.encode(preferences.toJson()),
    );
  }

  @override
  Future<void> setPDFPreferences(PDFPreferences preferences) async {
    _log.w('setPDFPreferences is not supported on web platform');
  }

  @override
  Future<void> applyDecorations(
    String id,
    List<ReaderDecoration> decorations,
  ) async {
    JsPublicationChannel().applyDecorations(
      id,
      jsonEncode(decorations.map((d) => d.toJson()).toList()),
    );
  }

  // COMMON PLAYBACK API - BEGIN
  @override
  Future<void> play(Locator? fromLocator) async {
    JsPublicationChannel.playAudio(
      locatorJson: fromLocator != null ? json.encode(fromLocator) : null,
    );
  }

  @override
  Future<void> stop() async {
    JsPublicationChannel.stopAudio();
  }

  @override
  Future<void> pause() async {
    JsPublicationChannel.pauseAudio();
  }

  @override
  Future<void> resume() async {
    JsPublicationChannel.resumeAudio();
  }

  @override
  Future<void> next() async {
    JsPublicationChannel.nextAudio();
  }

  @override
  Future<void> previous() async {
    JsPublicationChannel.previousAudio();
  }

  @override
  Future<bool> goToLocator(final Locator locator) async {
    try {
      await JsPublicationChannel.goToLocator(json.encode(locator));
      return true;
    } on PlatformException catch (e, stackTrace) {
      const pubID = 'unknown';
      throw ReadiumError(
        'Error when navigating to locator: ${e.message}',
        code: e.code,
        data: 'publication id: $pubID. locator: $locator',
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<bool> goToProgression(double progression) async => JsPublicationChannel.goToProgression(progression);

  @override
  Future<void> setNarrationSyncEnabled(bool enabled) async => JsPublicationChannel.setNarrationSyncEnabled(enabled);

  // COMMON PLAYBACK API - END

  // TTS API - BEGIN
  @override
  Future<void> ttsEnable(TTSPreferences? preferences) async {
    final prefsJson = json.encode(preferences?.toJson() ?? <String, dynamic>{});
    await JsPublicationChannel.ttsEnable(prefsJson);
  }

  @override
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() async {
    final voicesJson = await JsPublicationChannel.ttsGetAvailableVoices();
    final decoded = jsonDecode(voicesJson) as List<dynamic>;
    return decoded.whereType<Map<String, dynamic>>().map(ReaderTTSVoice.fromJson).toList();
  }

  @override
  Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage) async {
    JsPublicationChannel.ttsSetVoice(voiceIdentifier, lang: forLanguage);
  }

  @override
  Future<void> setDecorationStyle(
    ReaderDecorationStyle? utteranceDecoration,
    ReaderDecorationStyle? rangeDecoration,
  ) async {
    // NOTE: No TTS engine is wired up on web in Phase 1. The styles are forwarded
    // to the JS layer and stored for future use when the web TTS implementation arrives.
    JsPublicationChannel().setDecorationStyle(
      utteranceDecoration == null ? null : jsonEncode(utteranceDecoration.toJson()),
      rangeDecoration == null ? null : jsonEncode(rangeDecoration.toJson()),
    );
  }

  @override
  Future<void> ttsSetPreferences(TTSPreferences preferences) async {
    JsPublicationChannel.ttsSetPreferences(json.encode(preferences.toJson()));
  }
  // TTS API - END

  // AUDIOBOOK API - BEGIN
  @override
  Future<void> audioEnable({
    AudioPreferences? prefs,
    Locator? fromLocator,
  }) async {
    final prefsJson = json.encode(prefs?.toJson() ?? <String, dynamic>{});
    final locatorJson = fromLocator != null ? json.encode(fromLocator) : null;
    await JsPublicationChannel.audioEnable(
      prefsJson,
      fromLocatorJson: locatorJson,
    );
  }

  @override
  Future<void> audioSetPreferences(AudioPreferences prefs) async {
    JsPublicationChannel.setAudioPreferences(json.encode(prefs.toJson()));
  }

  @override
  Future<void> audioSeekBy(Duration offset) async {
    JsPublicationChannel.seekBy(offset.inMilliseconds / 1000.0);
  }
  // AUDIOBOOK API - END

  @override
  Future<Uint8List> getResourceBytes(String href) => JsPublicationChannel.getResourceBytes(href);

  @override
  Stream<ReadiumError> get onErrorEvent => _errorEventController.stream;
}
