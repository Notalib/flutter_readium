import 'dart:async';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';

export 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
export 'reader_widget_switch.dart';

/// Unified API for interacting with the Readium toolkits across platforms, providing methods for loading publications,
/// navigating content, controlling audio and TTS playback, and receiving updates on reader status and locator changes.
class FlutterReadium {
  /// Constructs a singleton instance of [FlutterReadium].
  factory FlutterReadium() {
    _singleton ??= FlutterReadium._();
    return _singleton!;
  }

  FlutterReadium._();

  static FlutterReadium? _singleton;

  static final _log = ReadiumLog.tag('FlutterReadium');

  static FlutterReadiumPlatform get _platform => FlutterReadiumPlatform.instance;

  /// Sets custom HTTP headers to be used for all network requests made by the reader.
  Future<void> setCustomHeaders(Map<String, String> headers) => _platform.setCustomHeaders(headers);

  /// Sets the log level for the plugin's internal logging.
  Future<void> setLogLevel(LogLevel level) => _platform.setLogLevel(level);

  /// Sets the default EPUB preferences that will be applied to all opened publications, unless overridden by publication-specific preferences.
  void setDefaultPreferences(EPUBPreferences preferences) {
    _platform.setDefaultPreferences(preferences);
  }

  /// Loads a publication from the given URL and returns a [Publication] object representing its metadata and structure. This does not open the publication for reading.
  Future<Publication> loadPublication(String pubUrl) => _platform.loadPublication(pubUrl);

  /// Opens a publication for reading from the given URL. This is required before any reading-related operations can be performed on the publication.
  ///
  /// Returns a [Publication] object representing the opened publication.
  Future<Publication> openPublication(String pubUrl) => _platform.openPublication(pubUrl).onError((err, _) {
    _log.e('OpenPublication error: ${err.toString()}');
    throw ReadiumException.fromError(err);
  });

  /// Closes the currently opened publication, if any. This will release any resources associated with the publication and reset the reader state.
  Future<void> closePublication() => _platform.closePublication();

  /// Stream emitting the current status of the visual reader.
  Stream<ReadiumReaderStatus> get onReaderStatusChanged => _platform.onReaderStatusChanged;

  /// Stream emitting the current text locator for the visual reader, such as when the user navigates to the next page or section of the publication.
  Stream<Locator> get onTextLocatorChanged => _platform.onTextLocatorChanged;

  /// Stream emitting the current time-based playback state (including audio Locator) during playback.
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged => _platform.onTimebasedPlayerStateChanged;

  /// Stream emitting any errors that occur within the reader, such as failed navigation or playback errors.
  Stream<ReadiumError> get onErrorEvent => _platform.onErrorEvent;

  /// Navigates backward in the publication, such as to the previous page or section.
  ///
  /// The exact behavior may depend on the publication's format and if audio or TTS is enabled.
  Future<void> goBackward() => _platform.goBackward();

  /// Navigates forward in the publication, such as to the next page or section.
  ///
  /// The exact behavior may depend on the publication's format and if audio or TTS is enabled.
  Future<void> goForward() => _platform.goForward();

  /// Skips to the next chapter in the publication's (flattened) table of contents.
  ///
  /// This is only applicable for publications that have a TOC and may not be supported for all formats.
  Future<void> skipToNextTOC({
    required final Publication publication,
    required final String currentTocHref,
  }) => _skipToTOCItem(publication, currentTocHref, 1);

  /// Skips to the previous chapter in the publication's (flattened) table of contents.
  ///
  /// This is only applicable for publications that have a TOC and may not be supported for all formats.
  Future<void> skipToPreviousTOC({
    required final Publication publication,
    required final String currentTocHref,
  }) => _skipToTOCItem(publication, currentTocHref, -1);

  /// Sets the EPUB preferences for the currently opened publication.
  ///
  /// These preferences will override any default preferences set by [setDefaultPreferences] for this publication.
  Future<void> setEPUBPreferences(EPUBPreferences preferences) => _platform.setEPUBPreferences(preferences);

  /// Sets the PDF preferences for the currently opened PDF publication.
  Future<void> setPDFPreferences(PDFPreferences preferences) => _platform.setPDFPreferences(preferences);

  /// Applies a list of decorations to the visual reader.
  ///
  /// The decorations will be identified by the given [id], which can be used to update or remove them later by calling this method again with the same [id].
  Future<void> applyDecorations(
    String id,
    List<ReaderDecoration> decorations,
  ) => _platform.applyDecorations(id, decorations);

  /// Enables TTS (text-to-speech) for the currently opened publication, optionally applying the given [preferences].
  Future<void> ttsEnable(TTSPreferences? preferences) => _platform.ttsEnable(preferences);

  /// Updates the TTS preferences for the current session without restarting TTS.
  Future<void> ttsSetPreferences(TTSPreferences preferences) => _platform.ttsSetPreferences(preferences);

  /// Sets the decoration styles used to highlight the active TTS utterance and the surrounding range.
  Future<void> setDecorationStyle(
    ReaderDecorationStyle? utteranceDecoration,
    ReaderDecorationStyle? rangeDecoration,
  ) => _platform.setDecorationStyle(utteranceDecoration, rangeDecoration);

  /// Returns all TTS voices available on the user's device.
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() async {
    await ReaderTTSVoiceUtils.ensureReadiumVoiceDataLoaded();

    return _platform.ttsGetAvailableVoices();
  }

  /// Sets the TTS voice to use, identified by [voiceIdentifier].
  ///
  /// If [forLanguage] is provided, the voice is applied only when the content language matches; otherwise it is used as the default voice.
  Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage) =>
      _platform.ttsSetVoice(voiceIdentifier, forLanguage);

  /// Starts playback from the given [fromLocator], or from the current position if `null`.
  Future<void> play(Locator? fromLocator) => _platform.play(fromLocator);

  /// Stops playback and tears down the active time-based navigator.
  ///
  /// Call [audioEnable] or [ttsEnable] again before resuming audio/TTS playback.
  Future<void> stop() => _platform.stop();

  /// Pauses playback at the current position.
  Future<void> pause() => _platform.pause();

  /// Resumes playback from the current position.
  Future<void> resume() => _platform.resume();

  /// Skips to the next playback unit, such as the next TTS utterance or one audio seek interval.
  Future<void> next() => _platform.next();

  /// Skips to the previous playback unit, such as the previous TTS utterance or one audio seek interval.
  Future<void> previous() => _platform.previous();

  /// Navigates the reader to the given [locator].
  ///
  /// Returns `true` if navigation succeeded, `false` otherwise.
  Future<bool> goToLocator(Locator locator) => _platform.goToLocator(locator);

  /// Navigates the reader to a specific progression in the current resource, where 0.0 is the start and 1.0 is the end.
  ///
  /// Returns `true` if navigation succeeded, `false` otherwise.
  Future<bool> goToProgression(double progression) => _platform.goToProgression(progression);

  /// Toggles narration↔visual sync for the current publication.
  ///
  /// `true` = follow narration / re-sync now (clears any manual override and
  /// immediately re-pans / re-positions to the last narration region).
  /// `false` = manual mode (the reader no longer auto-follows narration cues).
  ///
  /// For comic (DiViNa) publications this controls audio-driven panel auto-pan;
  /// future implementations will also cover Media Overlay. No-op for publication
  /// types that have no narration track.
  Future<void> setNarrationSyncEnabled(bool enabled) => _platform.setNarrationSyncEnabled(enabled);

  /// Stream emitting narration↔visual sync state changes.
  /// `true` = in sync; `false` = user took manual control (show re-sync UI).
  /// Currently fired by DiViNa comic navigators; future: Media Overlay.
  Stream<bool> get onNarrationSyncChanged => _platform.onNarrationSyncChanged;

  /// Enables audio playback for the currently opened publication, optionally applying [prefs] and starting from [fromLocator].
  Future<void> audioEnable({AudioPreferences? prefs, Locator? fromLocator}) =>
      _platform.audioEnable(prefs: prefs, fromLocator: fromLocator);

  /// Updates the audio preferences for the current session without restarting playback.
  Future<void> audioSetPreferences(AudioPreferences prefs) => _platform.audioSetPreferences(prefs);

  /// Seeks audio playback forward or backward by the given [offset].
  ///
  /// A negative [offset] seeks backward; a positive value seeks forward.
  Future<void> audioSeekBy(Duration offset) => _platform.audioSeekBy(offset);

  /// Navigates the reader to the physical page matching [index] within the Publication [pub].
  ///
  /// The lookup is case-insensitive and matched against the publication's page list.
  /// Throws a [ReadiumException] if no matching page link is found.
  Future<bool> toPhysicalPageIndex(
    final String index,
    final Publication pub,
  ) async {
    final pageIndex = index.toLowerCase();
    final pageList = pub.pageList;
    final pageLink = pageList.firstWhereOrNull(
      (final link) => link.title?.toLowerCase() == pageIndex,
    );
    if (pageLink == null) {
      throw const ReadiumException('Page link not found');
    }

    return goByLink(pageLink, pub);
  }

  /// Navigates the reader to the position corresponding to the given [link] within the Publication [pub].
  ///
  /// Throws a [ReadiumException] if the link cannot be resolved to a locator.
  Future<bool> goByLink(final Link link, final Publication pub) async {
    _log.d(() => 'Navigating to link: $link');

    final locator = pub.locatorFromLink(link);

    _log.d(locator);

    if (locator == null) {
      throw const ReadiumException('Link could not be resolved to locator');
    }

    return goToLocator(locator);
  }

  /// Searches for [searchKey] in the currently opened publication and returns a list of matching results.
  Future<List<TextSearchResult>> searchInPublication(String searchKey) async =>
      _platform.searchInPublication(searchKey);

  /// Fetches the raw bytes of the publication resource identified by [href].
  ///
  /// [href] is the publication-relative href as reported in an [ImageTapEvent]
  /// (e.g. `images/cover.png`). Returns the resource bytes.
  ///
  /// Implemented on iOS and Web. Throws [UnimplementedError] on Android until
  /// the kotlin-toolkit exposes an equivalent per-resource fetch API.
  Future<Uint8List> getResourceBytes(String href) => _platform.getResourceBytes(href);

  /// Returns a Flutter [ImageProvider] that lazily loads the EPUB resource at
  /// [href] via [getResourceBytes].
  ///
  /// On Web, prefer loading via [ImageTapEvent.srcUrl] using `Image.network`
  /// when available — it avoids the byte bridge. Use this provider as a
  /// fallback or for iOS/Android.
  ImageProvider imageProvider(String href) => ReadiumResourceImageProvider(href, _platform);

  ///////////////////////
  /// Private helpers ///
  ///////////////////////

  /// Helper method to skip to the next or previous TOC item based on the given [direction] (1 for next, -1 for previous).
  Future<void> _skipToTOCItem(
    Publication publication,
    String currentTocHref,
    int direction,
  ) async {
    final toc = publication.tocFlattened;
    if (toc.isEmpty) return;

    final curIndex = toc.indexWhere((l) => l.href == currentTocHref);

    // Throws exceptions so that they can either be handled to send a message to user or ignored
    if (curIndex == -1) {
      throw const ReadiumException('Could not find current toc index');
    }
    if (direction == 1 && curIndex == toc.length - 1) {
      throw const ReadiumException('At the last chapter');
    }

    final newIndex = (curIndex + direction).clamp(0, toc.length - 1);
    final locator = publication.locatorFromLink(toc[newIndex]);

    if (locator != null) {
      await goToLocator(locator);
    }
  }
}

/// An [ImageProvider] that fetches EPUB image resource bytes via the Readium
/// platform bridge ([FlutterReadiumPlatform.getResourceBytes]).
///
/// Usage:
/// ```dart
/// Image(image: ReadiumResourceImageProvider('images/cover.png', platform))
/// ```
@immutable
class ReadiumResourceImageProvider extends ImageProvider<ReadiumResourceImageProvider> {
  const ReadiumResourceImageProvider(this.href, this._platform);

  /// Publication-relative href of the image resource (e.g. `images/cover.png`).
  final String href;

  final FlutterReadiumPlatform _platform;

  @override
  Future<ReadiumResourceImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<ReadiumResourceImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    ReadiumResourceImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _loadBytes(key, decode),
    scale: 1.0,
    debugLabel: 'ReadiumResource($href)',
  );

  Future<ui.Codec> _loadBytes(
    ReadiumResourceImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await key._platform.getResourceBytes(key.href);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) => other is ReadiumResourceImageProvider && other.href == href;

  @override
  int get hashCode => href.hashCode;

  @override
  String toString() => 'ReadiumResourceImageProvider("$href")';
}
