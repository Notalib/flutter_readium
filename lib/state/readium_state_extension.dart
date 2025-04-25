import 'dart:math';

import '../_index.dart';

/// Used to check if the publication is changed.
String? _lastReadiumPublicationId;

extension ReadiumStateExtension on ReadiumState {
  Stream<ReadiumState> asStream() => FlutterReadium.stateStream;

  bool get hasPub => publication != null && opdsPublication != null;

  Uri? get pubCoverUri => opdsPublication?.coverUri ?? publication?.coverUri;

  bool get ttsOrAudiobook => ttsEnabled || (opdsPublication?.metadata.xIsAudiobook ?? false);

  Iterable<Link>? get toc => publication?.toc;
  Iterable<Link>? get pageList => publication?.pageList;

  Iterable<Link> get syncMediaNarration =>
      publication?.resources
          ?.where((final link) => link.type == MediaType.syncMediaNarration.value) ??
      const [];

  /// Extracts mp3s and removes duplicates.
  Iterable<Link> get mp3Resources =>
      publication?.resources
          ?.where((final link) => link.type == MediaType.mp3.value)
          .toSet()
          .toList() ??
      const [];

  Locator? get currentLocator {
    if (opening || preloadStatus.isLoading || !hasPub) {
      return null;
    }

    final locator = isEbook && !ttsEnabled ? textLocator : audioLocator;

    return locator;
  }

  bool get hasText {
    final opdsMetadata = opdsPublication?.metadata;

    return opdsMetadata?.xHasText == true || opdsMetadata?.xIsEbook == true;
  }

  List<String>? get pubLangs =>
      opdsPublication?.metadata.language ?? publication?.metadata.language;
  String? get pubLang => pubLangs?.first;

  bool get isWordHighlightMode => highlightMode.name == ReadiumHighlightMode.word.name;
  bool get isSentenceHighlightMode => highlightMode.name == ReadiumHighlightMode.sentence.name;

  bool get isEbook => opdsPublication?.metadata.xIsEbook == true;
  bool get isAudiobook => opdsPublication?.metadata.xIsAudiobook == true;
  bool get isAudiobookWithText => isAudiobook && hasText;
  bool get isAudiobookWithOutText => isAudiobook && !hasText;

  bool get readerReady => readerStatus.isOpen;
  bool get audioReady => audioStatus.isReady;

  /// Number of pages minus one in current chapter. Minimum 1 to avoid confusing slider widgets. Not
  /// sure what really makes sense here, maybe the slider should be disabled instead. Null if
  /// there's no widget.
  int? get chapterDivisions {
    final totalPages = textLocator?.locations?.totalPages;

    return totalPages == null ? null : max(totalPages - 1, 1);
  }

  Future<void> get awaitReaderReady async {
    R2Log.d('Waiting');

    if (!readerReady) {
      await for (final ready in asStream().map((final state) => state.readerReady)) {
        if (!ready) {
          continue;
        }

        break;
      }
    }

    R2Log.d('Done');
  }

  Future<void> get awaitAudioReady async {
    R2Log.d('Waiting');

    if (!audioReady) {
      await for (final ready in asStream().map((final state) => state.audioReady)) {
        if (!ready) {
          continue;
        }

        break;
      }
    }

    R2Log.d('Done');
  }

  Map<String, dynamic> toJsonMinified() => {
        ...toJson(),
        'publication': publication?.identifier,
        'opdsPublication': opdsPublication?.identifier,
      };

  void logDiff(final ReadiumState other) {
    R2Log.logMapDiff(
      toJsonMinified(),
      other.toJsonMinified(),
      prefix: '[READIUM STATE]',
      stackTraceBeginIndex: 5,
    );
  }
}

/// ################################################################################################
///
/// State Stream Extention
///
/// ################################################################################################

extension ReadiumStateStreamExtension on Stream<ReadiumState> {
  Stream<bool> get readerReady => map((final state) => state.readerReady).distinct();

  Stream<bool> get readerReadyUntilReaderClosed =>
      TakeUntilExtension(readerReady).takeUntil(readerClosed).asBroadcastStream();

  Stream<double?> get preloadProgress => map((final state) => state.preloadProgress).distinct();

  Stream<int?> get chapterDivisions => map((final state) => state.chapterDivisions).distinct();

  Stream<Locator?> get textLocator => map((final state) => state.textLocator).distinct();

  Stream<Locator?> get textLocatorUntilReadiumPubChanged => textLocator.takeUntilPublicationChanged;

  Stream<Locator?> get audioLocator => map((final state) => state.audioLocator).distinct();

  Stream<Locator?> get audioLocatorUntilReaderClosed =>
      TakeUntilExtension(audioLocator).takeUntil(readerClosed).asBroadcastStream();

  Stream<Locator?> get currentLocator => map((final state) => state.currentLocator).distinct();

  Stream<bool> get endOfPublication => map(
        (final state) => state.isEbook && !state.ttsEnabled
            ? state.readerStatus.isEndOfPublication
            : state.audioStatus.isEndOfPublication,
      ).distinct();

  Stream<bool> get audioMatchesText => map((final state) => state.audioMatchesText)
      .debounceTime(const Duration(milliseconds: 50))
      .distinct();

  Stream<Iterable<Link>?> get audiobookTOC =>
      audioLocator.distinct((final a, final b) => a?.href == b?.href).map((final locator) {
        final toc = FlutterReadium.state.toc;
        final tocUri = Uri.tryParse(locator?.href ?? '');

        if (toc == null) {
          return null;
        } else if (tocUri == null) {
          return toc;
        }

        return toc.setCurrentTocItem(tocUri);
      });

  Stream<Iterable<Link>?> get textbookTOC =>
      map((final state) => state.textLocator?.locations?.tocFragment).distinct().map(
        (final cssSelector) {
          final toc = FlutterReadium.state.toc;

          final locatorUri = Uri.tryParse(FlutterReadium.state.currentLocator?.href ?? '');

          if (toc == null ) {
            return null;
          } else if (locatorUri == null || cssSelector == null) {
            return toc;
          }

          return toc.setCurrentTocItem(locatorUri.replace(fragment: cssSelector));
        },
      );

  Stream<Iterable<Link>?> get toc => FlutterReadium.state.hasText ? textbookTOC : audiobookTOC;

  Stream<Iterable<Link>?> get tocFlatten => toc.map((final toc) => toc?.toFlattenedToc().toList());

  Stream<Publication?> get publication => map((final state) => state.publication)
      .distinct((final a, final b) => a?.identifier == b?.identifier);

  /// Emits an event when the publication is changed or closed.
  Stream<bool> get readiumPublicationChanged => publication.map((final publication) {
        final pubId = publication?.identifier;
        final lastReadiumPubId = _lastReadiumPublicationId;

        // Last readium publication is not set yet, no need to emit an event.
        if (lastReadiumPubId == null && pubId != null) {
          _lastReadiumPublicationId = pubId;

          return false;
        }

        if (lastReadiumPubId != pubId || pubId == null) {
          R2Log.d('Publication changed/closed $lastReadiumPubId -> $pubId');

          _lastReadiumPublicationId = pubId;
          return true;
        }

        return false;
      }).where((final event) => event);

  Stream<bool> get readerClosed =>
      readerStatus.where((final status) => status.isClose).map((final _) => true).distinct();

  Stream<bool> get ttsEnabled => map((final state) => state.ttsEnabled).distinct();

  Stream<bool> get ttsEnabledUntilReaderClosed =>
      TakeUntilExtension(ttsEnabled).takeUntil(readerClosed).asBroadcastStream();

  Stream<bool> get isInPlayingState =>
      map((final state) => state.playing || state.autoPlay).distinct();

  Stream<ReadiumAudioStatus> get audioStatus => map((final state) => state.audioStatus).distinct();

  Stream<ReadiumReaderStatus> get readerStatus =>
      map((final state) => state.readerStatus).distinct();

  Stream<ReadiumReaderProperties> get readerProperties =>
      map((final state) => state.readerProperties).distinct();

  Stream<ReadiumReaderProperties> get readerPropertiesUntilReaderClosed =>
      TakeUntilExtension(readerProperties).takeUntil(readerClosed).asBroadcastStream();

  Stream<ReadiumHighlightMode> get highlightMode =>
      map((final state) => state.highlightMode).distinct();

  Stream<ReadiumHighlightMode> get highlightModeUntilReaderClosed =>
      TakeUntilExtension(highlightMode).takeUntil(readerClosed).asBroadcastStream();

  Stream<Duration> get skipIntervalDuration =>
      map((final state) => state.skipIntervalDuration).distinct();

  Future<void> get waitOpenDone =>
      map((final state) => state.opening).firstWhere((final isOpening) => !isOpening);
}
