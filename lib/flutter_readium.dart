// You have generated a new plugin project without
// specifying the `--platforms` flag. A plugin project supports no platforms is generated.
// To add platforms, run `flutter create -t plugin --platforms <platforms> .` under the same
// directory. You can also find a detailed instruction on how to add platforms in the `pubspec.yaml`  at https://flutter.dev/docs/development/packages-and-plugins/developing-packages#plugin-platforms.

library;

import 'package:flutter/foundation.dart';

import '_index.dart';
import 'audio/readium_audio_handler_extension.dart';
import 'audio/readium_switch_audio_handler.dart';

export 'package:audio_service/audio_service.dart' show AudioProcessingState, PlaybackState;

export 'audio/index.dart';
export 'download/index.dart';
export 'exceptions/index.dart';
export 'extensions/index.dart';
export 'reader/index.dart';
export 'reader/reader_highlights.dart';
export 'shared/media_type.dart';
export 'shared/readium_shared.dart';
export 'state/index.dart';
export 'value_listenable_stream_extension.dart';
export 'xml/index.dart';

class FlutterReadium {
  FlutterReadium._();

  factory FlutterReadium() => instance;

  static final instance = FlutterReadium._();

  /// SSOT state for Flutter Readium.
  ///
  /// NOTE: Private property. To update the state use [updateState].
  static final _state = BehaviorSubject.seeded(const ReadiumState());

  /// Get current state.
  static ReadiumState get state => _state.value;

  /// Set current state.
  static set state(final ReadiumState state) {
    if (kDebugMode) {
      _state.value.logDiff(state);
    }

    _state.value = state;
  }

  /// Get state as stream.
  static Stream<ReadiumState> get stateStream => _state.stream;

  /// Helper property to update the state.
  static ReadiumStateType get updateState => state.update;

  static final audioHandler = ReadiumSwitchAudioHandler([
    Mp3AudioHandler(),
    TtsAudioHandler(),
  ]);

  /// Internal use only. Widget interface so audio handler can interact with the widget. Only
  /// non-null while a widget is visible.
  ReadiumReaderWidgetInterface? _reader;
  set reader(final ReadiumReaderWidgetInterface? reader) {
    R2Log.d('Set reader');

    _reader = reader;
  }

  static final _downloader = ReadiumDownloader.instance;
  static final _preloader = ReadiumPreloader.instance;

  static Future<void> init({
    required final String androidNotificationChannelId,
    required final String androidNotificationChannelName,
    final int downloadStep = 0,
    final bool downloadDebug = false,

    // Only for android.
    final ReadiumDownloadNotificationTapCallback? notificationTapCallback,
  }) async {
    final skipDuration = state.skipIntervalDuration;

    await Future.wait([
      AudioService.init(
        builder: () => audioHandler,
        config: AudioServiceConfig(
          androidNotificationChannelId: androidNotificationChannelId,
          androidNotificationChannelName: androidNotificationChannelName,
          androidNotificationOngoing: true,
          rewindInterval: skipDuration,
          fastForwardInterval: skipDuration,
        ),
      ),
      if (!kIsWeb)
        ReadiumDownloader.instance.init(
          step: downloadStep,
          debug: downloadDebug,
          notificationTapCallback: notificationTapCallback,
        ),
    ]);

    if (!kReleaseMode && !kIsWeb) await ReadiumPublicationChannel.dispose();
  }

  /// Opens a publication. Closes an old publication, if one is open.
  Future<Publication> openPublication(
    final OPDSPublication opdsPublication, {
    final Map<String, String>? headers,
    final Locator? initialLocator,
    final bool preload = true,
    final bool autoPlay = false,
    final bool ttsEnabled = false,
    final ReadiumReaderProperties readerProperties = const ReadiumReaderProperties(),
    final PhysicalPageIndexSemanticFormatter? physicalPageIndexSemanticsFormatter,
    final double? rewindTo,
  }) async {
    final opdsPubId = opdsPublication.identifier;
    final oldPub = state.publication;
    final oldOpdsPub = state.opdsPublication;

    // If publication is already open, don't reopen it (and don't stop playback as a result).
    if (oldPub != null && oldOpdsPub != null && oldOpdsPub.identifier == opdsPubId) {
      R2Log.d('Already opened ${oldPub.identifier}');

      FlutterReadium.updateState(
        readerProperties: readerProperties,
        autoPlay: autoPlay,
      );

      if (autoPlay) {
        play(
          rewindTo: rewindTo,
        );
      }

      return oldPub;
    }

    // Wait for old publication to finish closing.
    if (oldPub != null) {
      await closePublication();
    }

    R2Log.i('Opening $opdsPubId');
    R2Log.d(() => 'initialLocator: $initialLocator');

    if (!await hasInternetConnection() && !await _downloader.isDownloaded(opdsPublication)) {
      R2Log.d('Offline');
      throw const OfflineReadiumException('Device is offline - Publication is not downloaded');
    }

    FlutterReadium.updateState(
      opening: true,
      autoPlay: autoPlay,
      ttsEnabled: ttsEnabled,
      opdsPublication: opdsPublication,
      readerProperties: readerProperties,
      physicalPageIndexSemanticsFormatter: physicalPageIndexSemanticsFormatter,
      httpHeaders: headers,
      audioLocator: initialLocator,
      textLocator: initialLocator,
    );

    // Open new publication.
    final newPublication = await _getReadiumPublication(
      opdsPublication,
      headers: headers,
      preload: preload,
    );

    R2Log.d('Opened ${newPublication.identifier}');

    FlutterReadium.updateState(
      opening: false,
      publication: newPublication,
      opdsPublication: opdsPublication,
    );

    // The raw publication is now loaded. The rest happens reactively.
    // The `SwitchAudioHandler` and `ReaderWidget` separately listens on `publication` change and
    // updating the readium state.

    if (autoPlay) {
      play(
        rewindTo: rewindTo,
      );
    }

    R2Log.d('Done');
    return newPublication;
  }

  /// Closes the publication.
  Future<void> closePublication({final bool cleanup = true}) async {
    R2Log.d('Close');

    FlutterReadium.updateState(
      publication: null,
      opdsPublication: null,
      audioLocator: null,
      textLocator: null,
      audioMatchesText: true,
      opening: false,
      playing: false,
      httpHeaders: null,
      readerSwiping: false,
      audioStatus: ReadiumAudioStatus.none,
      readerStatus: ReadiumReaderStatus.close,
      preloadStatus: ReadiumPreloadStatus.none,
      preloadProgress: null,
      error: null,
    );

    await Future.wait([
      if (cleanup) this.cleanup() else stop(),
      _preloader.cancelAllPreload(),
      ReadiumPublicationChannel.dispose(),
    ]);

    R2Log.d('Done');
  }

  Future<void> stop() => audioHandler.stop();

  Future<void> cleanup() => audioHandler.cleanup();

  void setHighlightMode(final ReadiumHighlightMode mode) {
    FlutterReadium.updateState(
      highlightMode: mode,
    );
  }

  Future<void> toggleTTS({
    final bool ttsEnabled = false,
    final autoPlay = false,
  }) async {
    FlutterReadium.updateState(
      ttsEnabled: ttsEnabled,
    );

    if (!ttsEnabled) {
      pause();
      return;
    }

    final currentTextLocator = state.textLocator;

    if (currentTextLocator == null) {
      return;
    }

    go(currentTextLocator, autoPlay: autoPlay);
  }

  Future<void> setSkipInterval(final Duration duration) async {
    R2Log.d('Duration $duration');

    FlutterReadium.updateState(
      skipIntervalDuration: duration,
    );
  }

  Future<void> syncTextWithAudio() async {
    R2Log.d('Sync text with audio');

    final reader = _reader;
    final locator = state.audioLocator;
    final isAudioBookWithText = state.isAudiobookWithText;

    if (locator != null && reader != null) {
      await reader.go(locator, isAudioBookWithText: isAudioBookWithText);
    }
  }

  Future<void> go(
    final Locator locator, {
    final bool autoPlay = false,
  }) async {
    R2Log.d(locator);

    if (!state.ttsOrAudiobook && state.hasText) {
      await _readerGo(locator);
    } else {
      if (autoPlay) {
        await pause();
      }

      if (state.hasText) {
        _readerGo(locator);
      }

      FlutterReadium.updateState(
        autoPlay: autoPlay,
        audioStatus: ReadiumAudioStatus.loading,
        audioLocator: locator,
      );

      await audioHandler.go(locator);

      if (autoPlay) {
        play();
      }
    }

    R2Log.d('Done');
  }

  /// Tells the widget to go to the locator, at which point locatorState.value.text will be updated.
  Future<void> _readerGo(final Locator locator) async {
    final reader = _reader;
    if (reader == null) {
      R2Log.e(
        'No widget visible',
        data: locator,
      );
      return;
    }

    final state = FlutterReadium.state;
    final currentLocator = state.currentLocator;
    final newChapter = currentLocator?.hrefPath != locator.hrefPath;
    final isAudioBookWithText = state.isAudiobookWithText;

    FlutterReadium.updateState(
      readerStatus: newChapter ? ReadiumReaderStatus.loading : state.readerStatus,
      textLocator: locator,
    );

    return reader.go(locator, isAudioBookWithText: isAudioBookWithText);
  }

  /// Go to progression in chapter.
  Future<void> goToProgression(final double progression) async {
    R2Log.d('Go to $progression');

    // Go to locator with progression for ebooks without tts.
    if (state.hasPub && state.isEbook && !state.ttsEnabled) {
      final locator = state.textLocator?.mapLocations(
        (final locations) => locations
            .copyWith(
              customProgressionOverride: progression,
              progression: progression,
              cssSelector: null,
              domRange: null,
            )
            .copyWithPhysicalPageNumber(null)
            .copyWithPage(null),
      );

      if (locator != null) {
        return _readerGo(locator);
      } else {
        throw const ReadiumException('No locator found');
      }
    }

    final currentMediaItem = await audioHandler.mediaItem.first;

    final durationInMilliSec = currentMediaItem?.duration?.inMilliseconds;
    if (durationInMilliSec != null) {
      final progressionDuration =
          Duration(milliseconds: (progression * durationInMilliSec).toInt());

      return audioHandler.seek(progressionDuration);
    }
  }

  Future<void> play({final double? rewindTo}) async {
    R2Log.d('Starting ${audioHandler.inner.runtimeType}! - ${state.publication?.identifier}');

    return state.awaitAudioReady.timeout(
      const Duration(seconds: 5),
      onTimeout: () async {
        if (rewindTo != null) {
          await goToProgression(rewindTo);
        }
        R2Log.d('Timeout reached, Start playback anyway');
        audioHandler.play();
      },
    ).then((final _) async {
      if (rewindTo != null) {
        await goToProgression(rewindTo);
      }
      audioHandler.play();
    });
  }

  /// If [fade] is `true` the audio will fade on pause.
  Future<void> pause({final bool fade = false}) =>
      fade ? audioHandler.pauseFade() : audioHandler.pause();

  Future<void>? goLeft() => _reader?.goLeft();

  Future<void>? goRight() => _reader?.goRight();

  Future<void> skipToNext() async {
    await audioHandler.skipToNext();
    final mediaItem = audioHandler.mediaItem.value!;
    final queue = audioHandler.queue.value;
    R2Log.d('Current item: ${mediaItem.title}');
    R2Log.d('Queue pos: ${queue.indexOf(mediaItem) + 1}/${queue.length}');
  }

  Future<void> skipToPrevious() => audioHandler.skipToPrevious();

  Future<void> fastForward() => audioHandler.fastForward();

  Future<void> rewind() => audioHandler.rewind();

  Future<void> skipToNextParagraph() => audioHandler.skipToNextParagraph();

  Future<void> skipToPreviousParagraph() => audioHandler.skipToPreviousParagraph();

  Future<void> setPlaybackRate(final double rate) {
    R2Log.d('set speed to $rate');
    FlutterReadium.updateState(
      playbackRate: rate,
    );

    return audioHandler.setSpeed(rate);
  }

  Future<void> goByLink(
    final Link link, {
    final bool autoPlay = false,
  }) async {
    R2Log.d(() => 'Navigating to link: $link');

    final locator = locatorFromLink(link);

    R2Log.d(locator);

    if (locator == null) {
      throw const ReadiumException('Link could not be resolved to locator');
    }

    return go(locator, autoPlay: autoPlay);
  }

  Future<Publication> _getReadiumPublication(
    final OPDSPublication opdsPublication, {
    final Map<String, String>? headers,
    final bool preload = true,
  }) async =>
      await _downloader.getReadiumPublication(opdsPublication) ??
      await _loadRemoteReadiumPublication(
        opdsPublication,
        headers: headers,
        preload: preload,
      );

  Future<Publication> _loadRemoteReadiumPublication(
    final OPDSPublication opdsPublication, {
    final Map<String, String>? headers,
    final bool preload = true,
  }) async {
    if (!await hasInternetConnection()) {
      throw const OfflineReadiumException();
    }

    if (preload) {
      FlutterReadium.updateState(
        preloadStatus: ReadiumPreloadStatus.loading,
      );

      final preloadHref = opdsPublication.preloadLink?.href;
      R2Log.d('Preload href: $preloadHref');

      if (preloadHref != null) {
        final publicationCachedPath = await _preloader.preloadFile(
          opdsPub: opdsPublication,
          url: preloadHref,
          headers: headers,
          onProgress: (final progress) {
            if (state.preloadStatus.isCanceled) {
              return;
            }

            FlutterReadium.updateState(
              preloadProgress: progress,
              preloadStatus:
                  progress == 1.0 ? ReadiumPreloadStatus.complete : ReadiumPreloadStatus.loading,
            );
          },
        );

        if (publicationCachedPath == null) {
          FlutterReadium.updateState(
            preloadStatus: ReadiumPreloadStatus.canceled,
            preloadProgress: null,
          );

          throw const ReadiumException(
            'Preload canceled',
            type: ReadiumPreloadStatus.canceled,
          );
        }

        FlutterReadium.updateState(
          preloadStatus: ReadiumPreloadStatus.none,
          preloadProgress: null,
        );

        return ReadiumPublicationChannel.fromPath(
          publicationCachedPath,
          mediaType: opdsPublication.mediaType,
          headers: headers,
        );
      }

      throw const ReadiumException('Publication has no preload link!');
    }

    bool Function(MediaType) matchType(final Link link) => (final type) => link.type == type.value;
    final link = opdsPublication.links
        .firstWhereOrNull((final link) => openableMimeTypes.any(matchType(link)));

    // Would be better syntax with !? https://github.com/dart-lang/language/issues/361
    if (link == null) {
      throw const ReadiumException("Couldn't find link to open publication");
    }

    final url = link.href;
    final publicationUrl = url.substring(0, url.lastIndexOf('/') + 1);

    return ReadiumPublicationChannel.fromLink(
      url,
      headers: headers,
      mediaType: openableMimeTypes.firstWhere(matchType(link)),
      publicationUrl: publicationUrl,
    );
  }

  Locator? locatorFromLink(final Link link) {
    final pub = state.publication;
    if (pub == null) {
      return null;
    }

    final locator = pub.locatorFromLink(link);
    final index =
        pub.readingOrder.indexWhere((final element) => element.href.startsWith(locator!.href));
    final readingOrderLink = pub.readingOrder.elementAt(index);
    final progressions = pub.calculateProgressions(index: index == -1 ? 0 : index, progression: 0);
    final chapterDuration = readingOrderLink.duration;

    return locator?.copyWith(
      locations: locator.locationsOrEmpty.copyWith(
        progression: progressions.progression,
        totalProgression: progressions.totalProgression,
        xChapterDuration:
            chapterDuration == null ? null : const Duration(seconds: 1) * chapterDuration,
        xProgressionDuration: progressions.progressionDuration,
        xTotalProgressionDuration: progressions.progressionDuration,
      ),
    );
  }

  Future<void> toPhysicalPageIndex(final String index) async {
    final pageIndex = index.toLowerCase();
    final pageLists = state.pageList;
    final pageLink =
        pageLists?.firstWhereOrNull((final link) => link.title?.toLowerCase() == pageIndex);
    if (pageLink == null) {
      throw const ReadiumException('Page link not found');
    }

    return goByLink(pageLink);
  }

  void setTtsSpeakPhysicalPageIndex({final bool speak = false}) {
    R2Log.d(speak);

    FlutterReadium.updateState(
      ttsSpeakPhysicalPageIndex: speak,
    );
  }

  void setReaderProperties(final ReadiumReaderProperties properties) async {
    R2Log.d(properties);

    FlutterReadium.updateState(
      readerProperties: properties,
    );
  }

  Future<Locator?> getCurrentBookmark() async {
    R2Log.d('get current bookmark');

    final isAudioBookWithoutText = state.isAudiobookWithOutText;
    if (isAudioBookWithoutText) {
      return state.audioLocator;
      // `textLocator` should already contains all needed fragments. No need to call native.
    } else if (state.isEbook && !state.ttsEnabled) {
      return state.textLocator;
    }

    final locator = state.currentLocator;

    if (state.pageList?.isEmpty == true) {
      return locator;
    } else if (locator == null) {
      return null;
    }

    return getLocatorFragments(locator);
  }

  Future<Locator?> getLocatorFragments(final Locator locator) async {
    R2Log.d('get locator fragments');

    return _reader?.getLocatorFragments(locator);
  }

  Future<List<ReadiumTtsVoice>> getTtsVoices({final List<String>? fallbackLang}) async {
    R2Log.d('get TTS voices');

    return audioHandler.getTtsVoices(fallbackLang: fallbackLang);
  }

  Future<void> setTtsVoice(final ReadiumTtsVoice selectedVoice) {
    R2Log.d('set TTS voices');

    return audioHandler.setTtsVoice(selectedVoice);
  }

  Future<void> updateCurrentTtsVoicesReadium(final List<ReadiumTtsVoice>? preferredVoices) async {
    R2Log.d('Preferred voices $preferredVoices');

    FlutterReadium.updateState(
      currentTtsVoices: preferredVoices,
    );
  }

  void allowExternalSeeking(final bool allowExternalSeeking) {
    R2Log.d('Allow external seeking $allowExternalSeeking');

    FlutterReadium.updateState(
      allowExternalSeeking: allowExternalSeeking,
    );
  }

  void swapChapterInfo(final bool swapChapterInfo) {
    R2Log.d('Show publication info $swapChapterInfo');

    FlutterReadium.updateState(
      swapChapterInfo: swapChapterInfo,
    );
  }

  void setAppLanguage(final String? appLanguage) {
    R2Log.d('App language $appLanguage');

    FlutterReadium.updateState(
      appLanguage: appLanguage,
    );
  }

  Future<double?> getFreeDiskSpaceInMB() async =>
      await UtilsChannel.instance.getFreeDiskSpaceInMB();
}
