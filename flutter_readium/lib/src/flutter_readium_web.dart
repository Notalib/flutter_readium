import 'dart:async';
import 'dart:convert';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'js_publication_channel.dart';
import 'package:flutter/services.dart';

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
  Stream<Locator> get onTextLocatorChanged {
    return _locatorTextController.stream;
  }

  @override
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged {
    return _timebasedStateController.stream;
  }

  @override
  Stream<ReadiumReaderStatus> get onReaderStatusChanged {
    return _readerStatusController.stream;
  }

  @override
  Future<void> setCustomHeaders(Map<String, String> headers) =>
      throw UnimplementedError('setCustomHeaders is not implemented on web platform');

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
        R2Log.d('PUBLICATION WEB: Translations map key "$key" is longer than three letters.');
      }
    });
  }

  @override
  Future<Publication> openPublication(String pubUrl) async {
    // NOTE: For web, loadPublication and openPublication does the same thing,
    //
    // If calling the openPublication method outside of ReadiumWebView it will throw an error right away if there is no div with the id 'container'
    // additionally the openPublication method does currently not return a publication object
    R2Log.d(
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

  @override
  Future<String?> getLinkContent(Link link) {
    return getString(link);
  }

  static Future<String> getString(final Link link) async {
    // Get HTML string for full chapters, for example
    final linkString = json.encode(link);
    final resourceString = await JsPublicationChannel().getResource(linkString);
    return resourceString;
  }

  static Future<Uint8List> getBytes(final Link link) async {
    // TODO: Is this still needed for audio books with the new implementation
    final linkString = json.encode(link);
    final resourceBytesString = await JsPublicationChannel().getResource(linkString, asBytes: true);
    final byteList = jsonDecode(resourceBytesString).cast<int>();
    return Uint8List.fromList(byteList);
  }

  @override
  Future<void> goLeft({final bool animated = true}) async {
    JsPublicationChannel.goLeft();
  }

  @override
  Future<void> goRight({final bool animated = true}) async {
    JsPublicationChannel.goRight();
  }

  @override
  Future<void> skipToNext() async {
    R2Log.d('skipToNext is not implemented on web platform');
  }

  @override
  Future<void> skipToPrevious() async {
    R2Log.d('skipToPrevious is not implemented on web platform');
  }

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    defaultPreferences = preferences;
    JsPublicationChannel().setEPUBPreferences(json.encode(preferences.toJson()));
  }

  @override
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) async {
    R2Log.d('applyDecorations is not implemented on web platform');
  }

  // COMMON PLAYBACK API - BEGIN
  @override
  Future<void> play(Locator? fromLocator) => throw UnimplementedError('play is not implemented on web platform');

  @override
  Future<void> stop() => throw UnimplementedError('stop is not implemented on web platform');

  @override
  Future<void> pause() => throw UnimplementedError('pause is not implemented on web platform');

  @override
  Future<void> resume() => throw UnimplementedError('resume is not implemented on web platform');

  @override
  Future<void> next() => throw UnimplementedError('next is not implemented on web platform');

  @override
  Future<void> previous() => throw UnimplementedError('previous is not implemented on web platform');

  @override
  Future<bool> goToLocator(final Locator locator) async {
    try {
      await JsPublicationChannel.goToLocation(locator.hrefPath);
      return true;
    } on PlatformException catch (e, stackTrace) {
      final pubID = 'unknown';
      throw ReadiumError(
        'Error when navigating to locator: ${e.message}',
        code: e.code,
        data: 'publication id: $pubID. locator: $locator',
        stackTrace: stackTrace,
      );
    }
  }
  // COMMON PLAYBACK API - END

  // TTS API - BEGIN
  @override
  Future<void> ttsEnable(TTSPreferences? preferences) async {
    R2Log.d('ttsEnable is not implemented on web platform');
  }

  @override
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() async {
    R2Log.d('ttsGetAvailableVoices is not implemented on web platform');
    return [];
  }

  @override
  Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage) async {
    R2Log.d('ttsSetVoice is not implemented on web platform');
  }

  @override
  Future<void> setDecorationStyle(
    ReaderDecorationStyle? utteranceDecoration,
    ReaderDecorationStyle? rangeDecoration,
  ) async {
    R2Log.d('setDecorationStyle is not implemented on web platform');
  }

  @override
  Future<void> ttsSetPreferences(TTSPreferences preferences) async {
    R2Log.d('ttsSetPreferences is not implemented on web platform');
  }
  // TTS API - END

  // AUDIOBOOK API - BEGIN
  @override
  Future<void> audioEnable({AudioPreferences? prefs, Locator? fromLocator}) =>
      throw UnimplementedError('audioEnable is not implemented on web platform');

  @override
  Future<void> audioSetPreferences(AudioPreferences prefs) =>
      throw UnimplementedError('audioSetPreferences is not implemented on web platform');
  // AUDIOBOOK API - END

  @override
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged {
    // TODO: Implement when karaoke books are supported
    // throw UnimplementedError('get onTimebasedPlayerStateChanged is not implemented on web platform');
    return const Stream.empty();
  }

  @override
  Stream<ReadiumError> get onErrorEvent {
    throw UnimplementedError('get onErrorEvent is not implemented on web platform');
  }
}
