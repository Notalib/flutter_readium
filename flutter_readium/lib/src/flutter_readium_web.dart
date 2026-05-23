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
      ReadiumLog.w('Unknown ReadiumReaderStatus: $statusString');
    }
  }
}

class FlutterReadiumWebPlugin extends FlutterReadiumPlatform {
  static void registerWith(Registrar registrar) {
    FlutterReadiumPlatform.instance = FlutterReadiumWebPlugin();
  }

  static final StreamController<Locator> _locatorTextController = StreamController<Locator>.broadcast();
  static final StreamController<ReadiumTimebasedState> _timebasedStateController =
      StreamController<ReadiumTimebasedState>.broadcast();
  static final StreamController<ReadiumReaderStatus> _readerStatusController =
      StreamController<ReadiumReaderStatus>.broadcast();

  static void addTextLocatorUpdate(Locator locator) {
    _locatorTextController.add(locator);
  }

  static void addTimeBasedStateUpdate(ReadiumTimebasedState timebasedState) {
    _timebasedStateController.add(timebasedState);
  }

  static void addReaderStatusUpdate(ReadiumReaderStatus status) {
    _readerStatusController.add(status);
  }

  @override
  Stream<Locator> get onTextLocatorChanged => _locatorTextController.stream;

  @override
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged => _timebasedStateController.stream;

  @override
  Stream<ReadiumReaderStatus> get onReaderStatusChanged => _readerStatusController.stream;

  @override
  Future<void> setLogLevel(LogLevel level) async => ReadiumLog.setLevel(level);

  @override
  Future<void> setCustomHeaders(Map<String, String> headers) async {
    ReadiumLog.w('setCustomHeaders is not supported on web (browser controls HTTP headers)');
  }

  @override
  void setDefaultPreferences(EPUBPreferences preferences) {
    defaultPreferences = preferences;
  }

  @override
  Future<Publication> loadPublication(String pubUrl) async {
    Publication? publication;

    try {
      final publicationString = await JsPublicationChannel().getPublication(pubUrl);

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

  static Map<String, dynamic> _transformPublicationJson(final Map<String, dynamic> publicationJson) {
    // Transform 'links', 'readingOrder', 'resources', and 'tableOfContents' keys
    _transformKeyItems(publicationJson, 'links');
    _transformKeyItems(publicationJson, 'readingOrder');
    _transformKeyItems(publicationJson, 'resources');

    // rename key 'tableOfContents' to 'toc'
    if (publicationJson.containsKey('tableOfContents')) {
      publicationJson['toc'] = publicationJson.remove('tableOfContents');
    }

    // Transform 'children' key in 'toc'
    if (publicationJson.containsKey('toc') && publicationJson['toc'] is Map<String, dynamic>) {
      _transformKeyItems(publicationJson, 'toc');
      publicationJson['toc'] = _transformChildren(publicationJson['toc']);
    }

    // Transform 'translations' key in 'metadata'
    if (publicationJson.containsKey('metadata') && publicationJson['metadata'] is Map) {
      final metadataMap = publicationJson['metadata'] as Map<String, dynamic>;

      if (metadataMap.containsKey('authors') && metadataMap['authors'] is Map) {
        // rename key 'authors' to 'author'
        metadataMap['author'] = metadataMap.remove('authors');
        // remove 'items' wrapper if exists
        _transformKeyItems(metadataMap, 'author');

        for (final author in metadataMap['author']) {
          if (author is Map && author.containsKey('name') && author['name'] is Map) {
            final nameMap = author['name'] as Map<String, dynamic>;
            if (nameMap.containsKey('translations') && nameMap['translations'] is Map) {
              final translationsMap = nameMap['translations'] as Map<String, dynamic>;
              _validateTranslations(translationsMap);
              author['name'] = translationsMap;
            }
          }
        }
      }

      if (metadataMap.containsKey('title') && metadataMap['title'] is Map) {
        final titleMap = metadataMap['title'] as Map<String, dynamic>;
        if (titleMap.containsKey('translations') && titleMap['translations'] is Map) {
          final translationsMap = titleMap['translations'] as Map<String, dynamic>;

          _validateTranslations(translationsMap);

          metadataMap['title'] = translationsMap;
        }
      }

      if (metadataMap.containsKey('sortAs')) {
        final sortAs = metadataMap['sortAs'];
        if (sortAs is Map && sortAs['translations'] is Map) {
          final translations = sortAs['translations'] as Map;
          if (translations.isNotEmpty) {
            // Use the first value in the translations map
            metadataMap['sortAs'] = translations.values.first;
          } else {
            metadataMap['sortAs'] = null;
          }
        } else if (sortAs is! String) {
          metadataMap['sortAs'] = null;
        }
      }
    }

    return publicationJson;
  }

  static void _transformKeyItems(final Map<String, dynamic> json, final String key) {
    if (json.containsKey(key) && json[key] is Map) {
      final map = json[key] as Map<String, dynamic>;
      if (map.containsKey('items') && map['items'] is List) {
        json[key] = map['items'];
      }
    }
  }

  static List<dynamic> _transformChildren(final List<dynamic> items) => items.map((final item) {
    if (item is Map<String, dynamic> && item.containsKey('children')) {
      final children = item['children'];
      if (children is Map<String, dynamic> && children.containsKey('items')) {
        item['children'] = children['items'];
      }
      if (item['children'] is List) {
        item['children'] = _transformChildren(item['children']);
      }
    }
    return item;
  }).toList();

  static void _validateTranslations(Map<String, dynamic> translationsMap) {
    if (translationsMap.containsKey('undefined')) {
      translationsMap['und'] = translationsMap.remove('undefined');
    }

    // TODO: unknown if other languages also fails the validation, needs better handling
    translationsMap.forEach((final key, final value) {
      if (key.length > 3) {
        ReadiumLog.d('PUBLICATION WEB: Translations map key "$key" is longer than three letters.');
      }
    });
  }

  @override
  Future<Publication> openPublication(String pubUrl) async {
    // NOTE: For web, loadPublication and openPublication does the same thing,
    //
    // If calling the openPublication method outside of ReadiumWebView it will throw an error right away if there is no div with the id 'container'
    // additionally the openPublication method does currently not return a publication object
    ReadiumLog.d(
      'Cannot call openPublication outside of ReadiumWebView on web. Using getPublication instead to fetch the publication data.',
    );
    final publication = await loadPublication(pubUrl);
    return publication;
  }

  @override
  Future<void> closePublication() async {
    JsPublicationChannel().closePublication();
    return;
  }

  static Future<String> getString(final Link link) async {
    // Get HTML string for full chapters, for example
    final linkString = json.encode(link);
    final resourceString = await JsPublicationChannel().getResource(linkString);
    return resourceString;
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
    JsPublicationChannel().setEPUBPreferences(json.encode(preferences.toJson()));
  }

  @override
  Future<void> setPDFPreferences(PDFPreferences preferences) async {
    ReadiumLog.w('setPDFPreferences is not supported on web platform');
  }

  @override
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) async {
    ReadiumLog.w('applyDecorations is not implemented on web platform');
  }

  @override
  Future<List<TextSearchResult>> searchInPublication(String searchKey) async {
    ReadiumLog.w('searchInPublication is not implemented on web platform');
    return const [];
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
      await JsPublicationChannel.goToLocation(locator.hrefPath);
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
  Future<bool> goToProgression(double progression) async {
    ReadiumLog.w('goToProgression is not implemented on web platform');
    return false;
  }
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
    ReadiumLog.w('setDecorationStyle is not implemented on web platform');
  }

  @override
  Future<void> ttsSetPreferences(TTSPreferences preferences) async {
    JsPublicationChannel.ttsSetPreferences(json.encode(preferences.toJson()));
  }
  // TTS API - END

  // AUDIOBOOK API - BEGIN
  @override
  Future<void> audioEnable({AudioPreferences? prefs, Locator? fromLocator}) async {
    final prefsJson = json.encode(prefs?.toJson() ?? <String, dynamic>{});
    final locatorJson = fromLocator != null ? json.encode(fromLocator) : null;
    await JsPublicationChannel.audioEnable(prefsJson, fromLocatorJson: locatorJson);
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

  // TODO: Is this used anymore with the new JS implementation? If not, remove.
  @override
  Stream<ReadiumError> get onErrorEvent => const Stream.empty();
}
