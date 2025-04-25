import 'dart:convert';

import 'package:flutter/services.dart';

import '_index.dart';

const _channelName = 'dk.nota.flutter_readium/Publication';

const _channel = MethodChannel(_channelName);

const openableMimeTypes = [
  MediaType.readiumWebPubManifest,
  MediaType.readiumAudiobookManifest,
  MediaType.pdf,
];

enum _ReadiumPublicationChannelInvokeMethod {
  fromLink,
  fromPath,
  get,
  dispose,
}

class ReadiumPublicationChannel {
  /// Converts a local .epub file into a native Publication object.
  static Future<Publication> fromPath(
    final String path, {
    required final MediaType? mediaType,
    final Map<String, String>? headers,
  }) =>
      ReadiumPublicationChannel._fromInvokeMethod(
        _ReadiumPublicationChannelInvokeMethod.fromPath,
        [path, mediaType?.toList()],
        headers: headers,
      );

  /// Hopefully converts a remote epub directory into a native Publication object.
  static Future<Publication> fromLink(
    final String link, {
    required final MediaType mediaType,
    final Map<String, String>? headers,
    final String? publicationUrl,
  }) {
    final mediaTypeWithoutManifest = const {
      'application/webpub+json': MediaType.readiumWebPub,
      'application/audiobook+json': MediaType.readiumAudiobook,
      'application/divina+json': MediaType.divina,
    }[mediaType.value];
    if (mediaTypeWithoutManifest != null) {
      // Remove trailing 'manifest.json' from link, remove Manifest from mediaType.
      return _fromLink(
        link.substring(0, link.lastIndexOf('/') + 1),
        headers: headers,
        mediaType: mediaTypeWithoutManifest,
        publicationUrl: publicationUrl,
      );
    }
    return _fromLink(link, headers: headers, mediaType: mediaType);
  }

  static Future<Publication> _fromLink(
    final String link, {
    final Map<String, String>? headers,
    final MediaType mediaType = MediaType.epub,
    final String? publicationUrl,
  }) =>
      ReadiumPublicationChannel._fromInvokeMethod(
        _ReadiumPublicationChannelInvokeMethod.fromLink,
        [link, headers ?? const {}, mediaType.toList()],
        headers: headers,
        publicationUrl: publicationUrl,
      );

  static Future<Publication> _fromInvokeMethod(
    final _ReadiumPublicationChannelInvokeMethod method,
    final List<dynamic> arguments, {
    final Map<String, String>? headers,
    final String? publicationUrl,
  }) =>
      ReadiumPublicationChannel._fromChannel(
        _channel.invokeMethod(method.name, arguments),
        method,
        arguments,
      );

  static Future<Publication> _fromChannel(
    final Future<String?> retFuture,
    final _ReadiumPublicationChannelInvokeMethod method,
    final List<dynamic> arguments,
  ) async {
    String ret;
    try {
      ret = (await retFuture)!;
    } on PlatformException catch (e) {
      final type = e.intCode;
      throw OpeningReadiumException(
        '${e.code}: ${e.message ?? 'Unknown `PlatformException`'}',
        type: type == null ? null : OpeningReadiumExceptionType.values[type],
      );
    }
    final publicationString = ret;
    // R2Log.d('publicationString = ${splitIntoBase64Lines(publicationString)}');

    return Publication.fromJson(json.decode(publicationString) as Map<String, dynamic>);
  }

  /// Delete the native Publication object from a global id-to-Publication map.
  static Future<void> dispose() {
    R2Log.d('disposing publication');
    return _channel.invokeMethod(_ReadiumPublicationChannelInvokeMethod.dispose.name);
  }

  static Future<R> _get<R, T>(final T target) async => (await _channel.invokeMethod<R>(
        _ReadiumPublicationChannelInvokeMethod.get.name,
        [
          T == Link,
          if (T == Link) json.encode(target) else target,
          R == String,
        ],
      ))!;

  /// Fetch the text from the link.
  static Future<String> getString(final Link link) async => _get(link);

  /// Fetch the audio bytes from the link.
  static Future<Uint8List> getBytes(final Link link) async => _get(link);

  static Future<double?> getFreeDiskSpaceInBytes() async {
    final freeDiskSpace = await _channel.invokeMethod<double?>('getFreeDiskSpaceInBytes');
    return freeDiskSpace;
  }
}
