import 'dart:async';
import 'dart:convert';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_readium_web/js_publication_channel.dart';
import 'package:flutter/services.dart';

class FlutterReadiumWeb extends FlutterReadiumPlatform {
  static void registerWith([dynamic registrar]) {
    FlutterReadiumPlatform.instance = FlutterReadiumWeb();
  }

  static final StreamController<Locator> _locatorController = StreamController<Locator>.broadcast();

  static void addLocatorUpdate(Locator locator) {
    _locatorController.add(locator);
  }

  @override
  Future<Publication> openPublication(String pubUrl) async {
    Publication publication;

    try {
      final publicationString = await JsPublicationChannel().getPublication(pubUrl);

      var publicationJson = jsonDecode(publicationString) as Map<String, dynamic>;

      publicationJson = _transformPublicationJson(publicationJson);

      publication = Publication.fromJson(publicationJson);
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
    // Transform 'links', 'readingOrder', 'resources', and 'tableOfContents' keys
    _transformKeyItems(publicationJson, 'links');
    _transformKeyItems(publicationJson, 'readingOrder');
    _transformKeyItems(publicationJson, 'resources');
    _transformKeyItems(publicationJson, 'tableOfContents');

    // rename key 'tableOfContents' to 'toc'
    if (publicationJson.containsKey('tableOfContents')) {
      publicationJson['toc'] = publicationJson.remove('tableOfContents');
    }

    // Transform 'children' key in 'toc'
    if (publicationJson.containsKey('toc') && publicationJson['toc'] is List) {
      final tocList = publicationJson['toc'] as List<dynamic>;
      publicationJson['toc'] = _transformChildren(tocList);
    }

    // Transform 'translations' key in 'metadata'
    if (publicationJson.containsKey('metadata') && publicationJson['metadata'] is Map) {
      final metadataMap = publicationJson['metadata'] as Map<String, dynamic>;
      if (metadataMap.containsKey('title') && metadataMap['title'] is Map) {
        final titleMap = metadataMap['title'] as Map<String, dynamic>;
        if (titleMap.containsKey('translations') && titleMap['translations'] is Map) {
          final translationsMap = titleMap['translations'] as Map<String, dynamic>;

          if (translationsMap.containsKey('undefined')) {
            translationsMap['und'] = translationsMap.remove('undefined');
          }

          // TODO: unknown if other languages also fails the validation, needs better handling
          translationsMap.forEach((final key, final value) {
            if (key.length > 3) {
              R2Log.d('PUBLICATION WEB: Translations map key "$key" is longer than three letters.');
            }
          });
          metadataMap['title'] = translationsMap;
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

  @override
  Future<void> closePublication(String pubUrl) async {
    JsPublicationChannel().closePublication();
    return;
  }

  static Future<String> getString(final Link link) async {
    // Get HTML string for full chapters, for example
    final linkString = json.encode(link);
    final resourceString = await JsPublicationChannel().getResource(linkString);
    return resourceString;
  }

  static Future<Uint8List> getBytes(final Link link) async {
    // this is needed for audio books
    // TODO: This needs more testing
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
    R2Log.d('skipToNext not implemented in web version');
  }

  @override
  Future<void> skipToPrevious() async {
    R2Log.d('skipToPrevious not implemented in web version');
  }

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    R2Log.d('setEPUBPreferences not implemented in web version');
  }

  @override
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) async {
    R2Log.d('applyDecorations not implemented in web version');
  }

  @override
  Future<void> ttsEnable(TTSPreferences? preferences) async {
    R2Log.d('ttsEnable not implemented in web version');
  }

  @override
  Future<void> ttsStart(Locator? fromLocator) async {
    R2Log.d('ttsStart not implemented in web version');
  }

  @override
  Future<void> ttsStop() async {
    R2Log.d('ttsStop not implemented in web version');
  }

  @override
  Future<void> ttsPause() async {
    R2Log.d('ttsPause not implemented in web version');
  }

  @override
  Future<void> ttsResume() async {
    R2Log.d('ttsResume not implemented in web version');
  }

  @override
  Future<void> ttsNext() async {
    R2Log.d('ttsNext not implemented in web version');
  }

  @override
  Future<void> ttsPrevious() async {
    R2Log.d('ttsPrevious not implemented in web version');
  }

  @override
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() async {
    R2Log.d('ttsGetAvailableVoices not implemented in web version');
    return [];
  }

  @override
  Future<void> ttsSetVoice(String voiceIdentifier) async {
    R2Log.d('ttsSetVoice not implemented in web version');
  }

  @override
  Future<void> ttsSetDecorationStyle(
    ReaderDecorationStyle? utteranceDecoration,
    ReaderDecorationStyle? rangeDecoration,
  ) async {
    R2Log.d('ttsSetDecorationStyle not implemented in web version');
  }

  @override
  Future<void> ttsSetPreferences(TTSPreferences preferences) async {
    R2Log.d('ttsSetPreferences not implemented in web version');
  }

  @override
  Stream<ReadiumReaderStatus> get onReaderStatusChanged {
    R2Log.d('onReaderStatusChanged not implemented in web version');
    return const Stream.empty();
  }

  @override
  Stream<Locator> get onTextLocatorChanged {
    return _locatorController.stream;
  }

  @override
  Stream<Locator> get onAudioLocatorChanged {
    R2Log.d('onAudioLocatorChanged not implemented in web version');
    return const Stream.empty();
  }
}
