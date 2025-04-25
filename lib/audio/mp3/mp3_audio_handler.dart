import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../_index.dart';
import 'readium_mp3_progress.dart';

/// This was a BackgroundAudioTask isolate which runs Mp3.
class Mp3AudioHandler extends ReadiumAudioHandler {
  Mp3AudioHandler() {
    _player = _createNewAudioPlayer();
  }
  static const _onErrorMaxRetry = 3;
  static const bufferBeforePlayback = Duration(seconds: 5);
  static const androidMaxBuffer = Duration(minutes: 10);
  static Timer? _debounceTimer;

  final _seekToIndex = BehaviorSubject<int?>();
  final _playerDisposedStream = BehaviorSubject<bool>.seeded(false);

  late AudioPlayer _player;
  int _currentIndex = -1;
  var _onErrorRetried = 0;
  SyncMediaNarration? _currentNarration;
  Iterable<ChapterData>? _chapters;

  AudioPlayer _createNewAudioPlayer() {
    final audioPlayer = AudioPlayer(
      audioLoadConfiguration: AudioLoadConfiguration(
        darwinLoadControl: DarwinLoadControl(
          automaticallyWaitsToMinimizeStalling: false,
          preferredForwardBufferDuration: bufferBeforePlayback,
        ),
        androidLoadControl: AndroidLoadControl(
          bufferForPlaybackDuration: bufferBeforePlayback,
          maxBufferDuration: androidMaxBuffer,
        ),
      ),
    );
    return audioPlayer;
  }

  @override
  Future<void> publicationUpdated() async {
    final state = FlutterReadium.state;

    final pub = state.publication;
    final opdsPub = state.opdsPublication;
    final initialLocator = state.currentLocator;

    if (pub == null || opdsPub == null) {
      R2Log.d('Publication not set');
      return;
    }

    R2Log.d(() => 'pub: ${pub.identifier}, initialLocator: $initialLocator');

    final narrationResources = state.syncMediaNarration;

    if (narrationResources.isEmpty) {
      R2Log.d('No narration resources. Not an audio book?');
      _chapters = null;
      return;
    }

    final id = pub.identifier;
    final readingOrder = pub.readingOrder;

    // Prepare common metadata

    final coverUri = FlutterReadium.state.pubCoverUri;

    final chapters = _chapters = readingOrder.mapIndexed(
      (final index, final link) => ChapterData(
        getString: ReadiumPublicationChannel.getString,
        link: link,
        narrationLink: narrationResources.elementAt(index),
        mediaItem: MediaItem(
          // The id must be unique, or memoised functions of MediaItems return the wrong result.
          id: 'MP3-$id-$index',
          title: state.swapChapterInfo ? pub.title : link.title ?? '',
          // Switching album and artist value to display correct text order in Control Center.
          artist: state.swapChapterInfo ? link.title ?? '' : pub.title,
          album: pub.author ?? pub.artist,
          genre: pub.subjects,
          duration: const Duration(seconds: 1) * (link.duration ?? .0),
          displaySubtitle: pub.subtitle,
          displayDescription: pub.description,
          artUri: coverUri,
        ),
      ),
    );

    queue.value = chapters.map((final chapter) => chapter.mediaItem).toList();

    await reInit();
    R2Log.d('Done');
  }

  @override
  FutureOr<XmlDocument?> getDocument(final String href) => _chapters
      ?.firstWhereOrNull((final chapter) => chapter.link.href == href)
      ?.lazyDocument
      .then((final lazy) => lazy?.document);

  @override
  Future<void> stop() async {
    R2Log.d('stop');

    await _player.stop();

    R2Log.d('Done');

    // Shut down this task
    return super.stop();
  }

  @override
  Future<void> cleanup() async {
    R2Log.d('Clean');

    super.cleanup();

    await stop();
    await dispose();

    _currentIndex = -1;
    _currentNarration = null;
    _seekToIndex.value = null;
    _chapters = null;

    _player = _createNewAudioPlayer();

    R2Log.d('Done');
  }

  Future<void> dispose() async {
    _playerDisposedStream
      ..value = true
      ..value = false;

    return _player.dispose();
  }

  Future<void> init() async {
    R2Log.d('Init player');

    final state = FlutterReadium.state;

    final pub = state.publication;
    final opdsPub = state.opdsPublication;

    if (pub == null || opdsPub == null) {
      R2Log.e('Publication not set');
      return;
    }

    if (!opdsPub.hasDownloadLink) {
      R2Log.e('Publication has no download link');
      FlutterReadium.updateState(
        error: ReadiumError('Publication has no download link'),
      );
      return;
    }

    // Safe, since baseUrl just substrings downloadLink's href, which has been null checked.
    final baseUrl = opdsPub.baseUrl!;
    R2Log.d('Publication BaseURL: $baseUrl');

    _player = _createNewAudioPlayer();

    final audioSources = await ReadiumDownloader.instance.isDownloaded(opdsPub)
        ? _getLocalAudioSource(
            audioLinks: state.mp3Resources,
            bytes: ReadiumPublicationChannel.getBytes,
          ).toList()
        : _getRemoteAudioSource(
            audioLinks: state.mp3Resources,
            pubUrl: baseUrl,
            headers: state.httpHeaders,
          ).toList();

    R2Log.d('AudioSources.length = ${audioSources.length}');

    late final pState = playbackState.value;
    late final index = pState.queueIndex;
    late final position = pState.updatePosition;

    ReadiumMp3Progress? progress;

    final audioLocator = FlutterReadium.state.audioLocator;

    if (audioLocator != null) {
      progress = await _findAudioProgressFromLocator(audioLocator);
    } else if (index != null) {
      progress = ReadiumMp3Progress(index, position);
    }

    await _player
        .setAudioSources(
      audioSources,
      initialIndex: progress?.index,
      initialPosition: progress?.position,
    )
        .onError((final error, final stackTrace) {
      if (_onErrorRetried == 0) {
        FlutterReadium.updateState(
          error: ReadiumError('$error', stackTrace: stackTrace),
        );
      }

      return null;
    });

    // Update playbackState with initial progress.
    _broadcastState(
      playbackState.value.copyWith(
        queueIndex: progress?.index,
        updatePosition: progress?.position ?? Duration.zero,
      ),
    );

    R2Log.d('Did set audio source');

    _observeIndexChange();
    _observePlaybackProgress();
    _observePlayerIndexAndPosition();
    _observePlayerPlaybackEvent();
    _observerErrorEvent();
  }

  Future<void> reInit() async {
    R2Log.d('Re init player');

    final state = FlutterReadium.state;

    final pub = state.publication;
    final opdsPub = state.opdsPublication;

    if (pub == null || opdsPub == null) {
      R2Log.d('Publication not set');

      return;
    }

    await dispose();

    return init();
  }

  Future<void> _observeIndexChange() async {
    R2Log.d('Observing');

    final indexStream = _seekToIndex.takeUntilPublicationChanged
        .takeUntilPlayerDisposed(_playerDisposedStream)
        .debounceTime(const Duration(milliseconds: 300));

    await for (final index in indexStream) {
      R2Log.d('Seek to index $index');

      if (index == null) {
        R2Log.d('Index is null - ignore');

        continue;
      }

      _playerSeek(Duration.zero, index: index);

      // Calling `_setProgress` will make sure that view gets updated even the _player index is not.
      // TODO: Report this issue to just_audio where calling `seek` does not update the
      // `currentIndex` properly on index change.
      _setProgress(ReadiumMp3Progress(index, Duration.zero));
    }

    R2Log.d('Done');
  }

  Future<void> _observePlaybackProgress() async {
    R2Log.d('Observing');

    final indexOrPositionStream = playbackState.takeUntilPublicationChanged
        .takeUntilPlayerDisposed(_playerDisposedStream)
        .where(
          (final state) =>
              state.queueIndex != null && state.errorCode == null && state.errorMessage == null,
        )
        .map((final state) => ReadiumMp3Progress(state.queueIndex!, state.position))
        .throttleTime(const Duration(milliseconds: 300), trailing: true)
        .distinct();

    await for (final playerPosition in indexOrPositionStream) {
      R2Log.d(
        () => 'Changed ${FlutterReadium.state.opdsPublication?.identifier} - $playerPosition',
      );

      final state = FlutterReadium.state;
      if (state.opening || !state.hasPub) {
        R2Log.d('Player is opening state - ignore process position');

        continue;
      }
      try {
        _setProgress(playerPosition);
      } on Object catch (e) {
        R2Log.e(e, data: playerPosition);
      }
    }

    R2Log.d('Done');
  }

  Future<void> _setProgress(final ReadiumMp3Progress progress) async {
    R2Log.d('$progress');

    final pub = FlutterReadium.state.publication;

    late final errorData = {
      'OpdsPublication': pub,
      'progress': progress,
    };

    if (pub == null) {
      R2Log.e('publication not set');

      return;
    }

    final index = progress.index;
    final position = progress.position;

    final chapter = _chapters?.elementAt(index);
    if (chapter == null) {
      R2Log.e(
        'Chapter not found',
        data: errorData,
      );
      return;
    }

    // Find current narration and corresponding paragraph.
    final isCurrent = _currentIndex == index && _currentNarration?.contains(position) == true;

    if (!isCurrent) {
      _currentIndex = index;
      final narration = _currentNarration = (await chapter.narration)?.findFuzzy(position);

      final cssSelector = narration?.cssSelector;
      if (cssSelector == null) {
        R2Log.e(
          'Narration not found',
          data: errorData,
        );
        return;
      }
    }

    R2Log.d(() => 'Narration: $_currentNarration');

    final chapterDuration = chapter.mediaItem.duration!;
    final progression = (position / chapterDuration).clamp(0.0, 1.0);
    final progressions = pub.calculateProgressions(index: index, progression: progression);

    final locator = _currentNarration?.toLocator(
      title: chapter.link.title,
      progression: progression,
      totalProgression: progressions.totalProgression,
      chapterDuration: chapterDuration,
      totalProgressionDuration: progressions.totalProgressionDuration,
      progressionDuration: position,
      // Add 1 to index to properly convert playlist index to readium position.
      // Position must be >=1.
      position: index + 1,
    );

    if (locator == null) {
      R2Log.e(
        'Could not convert syncNarration to locator',
        data: {
          'narration': _currentNarration,
          ...errorData,
        },
      );

      return;
    }

    return super.setProgress(locator);
  }

  @override
  Future<void> click([final MediaButton button = MediaButton.media]) async {
    R2Log.d('Click - $button');

    switch (button) {
      case MediaButton.media:
        return super.click(button);
      case MediaButton.next:
        return await fastForward();
      case MediaButton.previous:
        return await rewind();
    }
  }

  @override
  Future<void> play() async {
    R2Log.d('play');

    if (!FlutterReadium.state.hasPub) {
      R2Log.d('No publication is set - prevent play');

      return;
    }

    _broadcastState(
      playbackState.value.copyWith(
        playing: true,
        errorCode: null,
        errorMessage: null,
      ),
    );

    // Make sure playback rate is set before play.
    setSpeed(FlutterReadium.state.playbackRate);

    await _player.setVolume(1.0);

    // Must not await. Doesn't complete when playback starts. Maybe completes when playback
    // stops.
    _player.play();

    super.play();
  }

  @override
  Future<void> pause() async {
    R2Log.d('pause');
    _broadcastState(playbackState.value.copyWith(playing: false));
    _player.pause();

    super.pause();
  }

  @override
  Future<void> pauseFade() async {
    R2Log.d('pause fade');

    var volume = 100;

    while (volume >= 0) {
      await Future.delayed(const Duration(milliseconds: 200));
      volume = volume - 10;
      await _player.setVolume(volume / 100);
    }

    return pause();
  }

  Future<void> _playerSeek(
    final Duration position, {
    final int? index,
    int retry = 0,
  }) async {
    late final logData = {
      'position': position,
      'index': index,
      'retry': retry,
    };

    try {
      R2Log.d(logData);

      // Should not be awaited. since future seeks will be blocked.
      _player.seek(position, index: index).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          R2Log.d(() => 'Timeout Retry seek $logData');

          if (retry > 5) {
            R2Log.e(
              'Max retry reached',
              data: {
                'pubId': FlutterReadium.state.opdsPublication?.identifier,
                ...logData,
              },
            );
            stop();

            return;
          }

          _playerSeek(position, index: index, retry: ++retry);
        },
      ).onError((final error, final stackTrace) {
        R2Log.e(error ?? 'Error on seek', data: logData);
      });
    } on Object catch (error) {
      R2Log.e(
        error,
        data: logData,
      );
    }
  }

  Future<void> _playerSeekToNext() async {
    final toIndex = (playbackState.value.queueIndex ?? 0) + 1;

    if (toIndex >= queue.value.length) {
      R2Log.d('End of playlist');
      return;
    }

    _seekToIndex.value = toIndex;

    R2Log.d('$toIndex');
  }

  Future<void> _playerSeekToPrevious() async {
    final toIndex = (playbackState.value.queueIndex ?? 0) - 1;

    if (toIndex < 0) {
      R2Log.d('Start of the playlist');
      return;
    }

    _seekToIndex.value = toIndex;

    R2Log.d('$toIndex');
  }

  @override
  Future<void> skipToNext() async {
    if (!_player.hasNext) {
      R2Log.d('Seeking to end');

      final position = _chapters?.elementAt(playbackState.value.queueIndex ?? 0).mediaItem.duration;

      return _playerSeek(position ?? Duration.zero);
    }
    R2Log.d('skip to next');
    return _playerSeekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position >= const Duration(seconds: 5) || playbackState.value.queueIndex == 0) {
      R2Log.d('Seeking to start of current chapter');
      return _playerSeek(Duration.zero);
    }
    R2Log.d('Skip to previous');
    return _playerSeekToPrevious();
  }

  @override
  Future<void> seek(final Duration position) => _playerSeek(position);

  Future<void> _seekRelative(final Duration delta) async {
    final chapters = _chapters;
    if (chapters == null) {
      // Can't happen.
      R2Log.d('$delta but NO DATA!');
      return;
    }

    final currentIndex = playbackState.value.queueIndex;
    var index = currentIndex ?? 0;
    var position = _player.position + delta;
    Duration currentDuration() => chapters.elementAt(index).mediaItem.duration ?? Duration.zero;
    // Handle seeking before beginning of current chapter.
    while (position < Duration.zero) {
      if (index <= 0) {
        // At start of book.
        position = Duration.zero;
        break;
      } else {
        --index;
        position += currentDuration();
      }
    }
    // Handle seeking after end of current chapter.
    while (position >= currentDuration()) {
      if (index >= chapters.length - 1) {
        // At end of book.
        position = currentDuration();
        break;
      } else {
        position -= currentDuration();
        ++index;
      }
    }
    R2Log.d(
      '$delta: [$currentIndex]@${_player.position} -> [$index]@$position',
    );

    if (currentIndex != index) {
      FlutterReadium.updateState(
        audioStatus: ReadiumAudioStatus.loading,
      );
    }

    return _playerSeek(position, index: index);
  }

  @override
  Future<void> fastForward() => _seekRelative(FlutterReadium.state.skipIntervalDuration);

  @override
  Future<void> rewind() => _seekRelative(-FlutterReadium.state.skipIntervalDuration);

  @override
  Future<void> setSpeed(final double speed) async {
    R2Log.d('$speed');
    _broadcastState(playbackState.value.copyWith(speed: speed));
    return _player.setSpeed(speed);
  }

  @override
  Future<void> go(final Locator locator) async {
    R2Log.d(() => 'Seek to locator $locator');

    final audioPosition = await _findAudioProgressFromLocator(locator);

    if (audioPosition == null) {
      R2Log.e(
        'No audioPosition found!',
        data: locator,
      );

      return;
    }

    final index = audioPosition.index;
    final position = audioPosition.position;

    await _playerSeek(position, index: index);

    R2Log.d('Done');
  }

  Future<ReadiumMp3Progress?> _findAudioProgressFromLocator(final Locator locator) async {
    onErr(final String message) => R2Log.e(
          message,
          data: locator,
        );

    final chapters = _chapters;
    if (chapters == null) {
      onErr('No chapters - Could not find position');

      return null;
    }

    // Find chapter.
    final href = locator.href;
    final index = chapters.indexWhere((final c) => c.link.href == href);
    if (index == -1) {
      onErr('Unknown chapter $href');

      return null;
    }

    final locations = locator.locations;
    final timeFragment = locations?.timeFragment;

    if (timeFragment != null) {
      R2Log.d('Set position to index: $index timeFragment.begin: ${timeFragment.begin}');

      return ReadiumMp3Progress(index, timeFragment.begin);
    }

    final chapter = chapters.elementAt(index);

    final cssSelector = locations?.domRange?.start.cssSelector ?? locations?.cssSelector;

    final progression = locations?.progression;
    if (progression != null && cssSelector == null) {
      final duration = chapter.mediaItem.duration ?? Duration.zero;
      final position = duration * progression;

      R2Log.d('No cssSelector - Set position to index: $index progressionDuration: $position');

      return ReadiumMp3Progress(index, position);
    }

    if (cssSelector == null) {
      onErr('No cssSelector - Set position to start of chapter $index');

      return ReadiumMp3Progress(index, Duration.zero);
    }

    if (FlutterReadium.state.isAudiobookWithOutText) {
      final progressionDuration = locator.locations?.xProgressionDuration;
      if (progressionDuration != null) {
        R2Log.d('Audiobook without text - progressionDuration: $progressionDuration');

        return ReadiumMp3Progress(index, progressionDuration);
      }

      R2Log.d('Audiobook without text - No position found - Navigate to start of chapter');

      return ReadiumMp3Progress(index, Duration.zero);
    }

    // Progression is not known, but we have a location in the text. Try to find the part of the
    // audio corresponding to the text.
    final document = await chapter.lazyDocument;
    if (document == null) {
      onErr('Document fetch failed - Set position to start of chapter $index');

      return ReadiumMp3Progress(index, Duration.zero);
    }

    final boundary = locations?.domRange?.start;
    final boundaryNode = document.querySelector(cssSelector);
    if (boundaryNode == null) {
      onErr('No Boundary - $cssSelector, $boundaryNode - Set position to start of chapter $index');

      return ReadiumMp3Progress(index, Duration.zero);
    }

    final boundaryOffset = boundary?.charOffset ?? 0;
    final pos = DomPosition(node: boundaryNode, charOffset: boundaryOffset).local();
    final narrationsWithNonNullText =
        (await chapter.narration)?.narrationsWithNonNullText ?? const [];
    for (final narration in narrationsWithNonNullText) {
      final selector = narration.cssSelector;
      if (selector == null) {
        continue;
      }
      final element = document.querySelector(selector);
      if (element == null) {
        continue;
      }
      final blockPos = pos.offsetInAncestor(element);
      if (blockPos != null) {
        final audioBegin = narration.audioBegin;
        if (audioBegin == null) {
          onErr('Missing audio.begin - Set position to start of chapter $index');

          return ReadiumMp3Progress(index, Duration.zero);
        }
        final audioEnd = narration.audioEnd ?? audioBegin;
        // At least 1, to avoid divide by 0.
        final textLength = max(element.domText().length, 1);
        final blockProgression = (blockPos.charOffset / textLength).clamp(0.0, 1.0);

        // For page break use the end audio position to make sure either page break element or next
        // element receives highlight.
        final audioPos = blockPos.isPageBreak
            ? audioEnd
            : audioBegin + (audioEnd - audioBegin) * blockProgression;

        R2Log.d(
          () =>
              'Found position[$index ($href)] $audioBegin ≤ $audioPos ≤ $audioEnd -- narration: $narration',
        );

        return ReadiumMp3Progress(index, audioPos);
      }
    }

    R2Log.d(() => '$cssSelector, $boundaryNode, $boundaryOffset');

    onErr('Position not found - Set position to start of chapter $index');

    return ReadiumMp3Progress(index, Duration.zero);
  }

  Iterable<IndexedAudioSource> _getRemoteAudioSource({
    required final Iterable<Link> audioLinks,
    required final String pubUrl,
    final Map<String, String>? headers,
  }) sync* {
    // Use remote book.
    R2Log.d('BEGIN AUDIO LIST');
    for (final link in audioLinks) {
      // Makes sure that slash is correctly added to prevent getting 404 from server.
      final bookUrlNoTrailingSlash =
          pubUrl.endsWith('/') ? pubUrl.substring(0, pubUrl.length - 1) : pubUrl;

      final linkHref = link.href;
      final linkHrefNoLeadingSlash = linkHref.startsWith('/') ? linkHref.substring(1) : linkHref;

      final uri = Uri.parse('$bookUrlNoTrailingSlash/$linkHrefNoLeadingSlash');
      // R2Log.d(' - $uri');

      // Seems that cashed file will get lost and cause playback error.
      // yield LockCachingAudioSource(uri, headers: headers);
      yield AudioSource.uri(
        uri,
        headers: headers,
      );
    }

    R2Log.d('END AUDIO LIST');
  }

  Iterable<IndexedAudioSource> _getLocalAudioSource({
    required final Iterable<Link> audioLinks,
    required final Future<Uint8List> Function(Link) bytes,
  }) sync* {
    // Use downloaded book.

    for (final link in audioLinks) {
      yield _ReadiumAudioSource(
        getBytes: bytes,
        link: link,
      );
    }
    // Uncomment if using simulator.
    // if (kDebugMode && Platform.isIOS) {
    //   // Main thread (not Flutter thread) hangs unless doing this! Can't load files while the main
    //   // thread is blocked, and if just_audio is blocking the main thread, then the files never
    //   // load… Since it immediately tries loading all files instead of just the first one to play,
    //   // there's no advantage to not loading immediately, anyway. Hope all phones have enough
    //   // memory to load the whole audiobook.
    //   for (final source in audioSources as List<_ReadiumAudioSource>) {
    //     R2Log.d(
    //       'Preloading ${source.link.href}, otherwise app main thread hangs!! '
    //       '(https://github.com/ryanheise/just_audio/issues/526)',
    //     );
    //     await source._data;
    //   }
    // }
  }

  /// init the Mp3 audio handler
  /// This piece of just_audio -> audio_service glue is implemented based on:
  /// https://github.com/ryanheise/audio_service/blob/master/audio_service/example/lib/example_multiple_handlers.dart
  Future<void> _observePlayerPlaybackEvent() async {
    R2Log.d('Observing');

    // Propagate all events from the audio player to AudioService clients.
    _toPlaybackState(_player.playbackEvent);

    final stream = _player.playbackEventStream.takeUntilPublicationChanged
        .takeUntilPlayerDisposed(_playerDisposedStream);

    try {
      await for (final event in stream) {
        R2Log.d('Event changed: $event');

        if (event.processingState == ProcessingState.idle && event.errorMessage == 'source error') {
          final internetStatus = await hasInternetConnection();
          final err = ReadiumError(
            internetStatus ? 'Unknown source error' : 'No internet connection',
            code: internetStatus ? event.errorCode.toString() : '1009',
            data: event.toString(),
          );
          _logReadiumError(err);
        }

        _toPlaybackState(event);
      }
    } on Object catch (error) {
      if (_onErrorRetried < _onErrorMaxRetry) {
        R2Log.d('Got proxy error - retry');

        _onErrorRetried += 1;

        await _reInitOnError(_onErrorRetried);
      } else {
        // An error was received, we should log it and stop player, so we don't end up skipping over tracks.
        // It can resume from where it got to, when the user presses play again.
        stop();

        final err = MaxRetryReadiumError(data: error);

        R2Log.e(err);

        _broadcastState(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            errorCode: int.tryParse(err.code ?? ''),
            errorMessage: err.message,
            playing: false,
          ),
        );
      }
    }

    R2Log.d('Done');
  }

  Future<void> _observerErrorEvent() async {
    R2Log.d('Observing error stream');
    final stream = _player.errorStream.takeUntilPublicationChanged
        .takeUntilPlayerDisposed(_playerDisposedStream);

    await for (final error in stream) {
      final internetStatus = await hasInternetConnection();
      if (_onErrorRetried < _onErrorMaxRetry && internetStatus) {
        _onErrorRetried += 1;

        R2Log.d('On Error. Attempt: $_onErrorRetried');

        await _reInitOnError(_onErrorRetried);
      } else {
        R2Log.d('On error - stop playback');

        _onErrorRetried = 0;
        stop();

        // When play stop due to a lack of internet, the returned error code is 0 on Android.
        // If we get code 0 and there is no internet connection, we return a 1009
        if (error.code == 0 && !internetStatus) {
          R2Log.d('No internet connection - stop playback');

          final err = ReadiumError(
            'No internet connection',
            code: '1009',
            data: error.toString(),
          );
          _logReadiumError(err);

          _broadcastState(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.error,
              errorCode: 1009,
              errorMessage: err.message,
              playing: false,
            ),
          );

          return;
        }

        final err = ReadiumError(
          error.message.toString(),
          code: error.code.toString(),
          data: error.toString(),
        );
        _logReadiumError(err);

        _broadcastState(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            errorCode: int.tryParse(err.code ?? ''),
            errorMessage: err.message,
            playing: false,
          ),
        );
      }
    }
  }

  Future<void> _observePlayerIndexAndPosition() async {
    // WORKAROUND:
    // The index and position could sometimes get out of sync, means that just_audio changes the
    // index but the position still is on the previous track.
    // TODO: Report the issue to just_audio.

    DateTime? lastUpdateTime;
    int? lastIndex;

    R2Log.d('Observing');

    final stream = CombineLatestStream.combine2<int?, Duration, ReadiumMp3Progress?>(
      _player.currentIndexStream,
      _player.positionStream,
      (final index, final position) {
        if (index != lastIndex &&
            lastUpdateTime != null &&
            _player.playbackEvent.updateTime.isAtSameMomentAs(lastUpdateTime!)) {
          R2Log.d('Index & position is out of sync - DO NOT update playbackState $index/$position');

          return null;
        }

        lastIndex = index;
        lastUpdateTime = _player.playbackEvent.updateTime;

        if (index != null) {
          mediaItem.value = queue.value[index];
          return ReadiumMp3Progress(index, position);
        }

        return null;
      },
    ).takeUntilPublicationChanged.takeUntilPlayerDisposed(_playerDisposedStream);

    await for (final progress in stream) {
      R2Log.d('Progress changed: $progress');

      final index = progress?.index;
      final position = progress?.position;

      if (playbackState.value.hasError) {
        R2Log.d(
          'Player has error ${playbackState.value.error} - DO NOT update playbackState $index/$position',
        );

        continue;
      }

      if (index != null && position != null) {
        _broadcastState(
          playbackState.value.copyWith(
            queueIndex: index,
            updatePosition: position,
          ),
        );
      }
    }
    R2Log.d('Done');
  }

  /// Current just_audio state to audio_service.
  void _toPlaybackState(final PlaybackEvent event) {
    R2Log.d(event.toString());

    final playerPlaybackState = playbackState.value.copyWith(
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      speed: _player.speed,
    );

    final hasError =
        playerPlaybackState.errorCode != null || playerPlaybackState.errorMessage != null;

    if (hasError) {
      return _broadcastState(
        playerPlaybackState.copyWith(
          playing: false,
          processingState: AudioProcessingState.error,
        ),
      );
    }

    _broadcastState(
      playerPlaybackState.copyWith(
        bufferedPosition: _player.bufferedPosition,
        playing: _player.playing,
      ),
    );
  }

  /// Broadcast current just_audio state to audio_service.
  void _broadcastState(final PlaybackState state) {
    R2Log.d(state.toDebugString());

    final readiumState = FlutterReadium.state;

    playbackState.value = state.copyWith(
      controls: [
        MediaControl.rewind,
        if (state.playing) MediaControl.pause else MediaControl.play,

        MediaControl.fastForward,

        // NOTE: We need to add `skipToPrevious` and `skipToNext` in order to make the headset
        // buttons works on iOS.
        if (Platform.isIOS) ...[
          MediaControl.skipToPrevious,
          MediaControl.skipToNext,
        ],
      ],
      systemActions: {
        if (readiumState.allowExternalSeeking) MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
    );

    // Note: Error is already broadcasted. reset the error state.
    if (state.hasError) {
      playbackState.value = playbackState.value.copyWith(
        processingState: AudioProcessingState.ready,
        errorCode: null,
        errorMessage: null,
      );

      _onErrorRetried = 0;
    }
  }

  Future<void> _reInitOnError(final int attempt) async {
    R2Log.d('Retry: $attempt');

    final playing = playbackState.value.playing;

    // Wait at least 1 second between each retry.
    await Future.delayed(const Duration(seconds: 1));

    await _player.stop();

    await reInit();

    if (playing) {
      R2Log.d('Was in playing state - start playback');

      Future.delayed(const Duration(seconds: 1)).then((final _) {
        play();
      });
    }

    R2Log.d('Done Retry: $attempt');
  }

  void _logReadiumError(final ReadiumError readiumError) {
    // Errors should come through the error stream, but sometimes they just don't.
    // So we also look for signs of errors in the playback event stream,
    // we debounce the errors to ensure we don't log the same error multiple times.

    const debounceDuration = Duration(seconds: 1);
    if (_debounceTimer?.isActive ?? false) {
      return;
    }

    _debounceTimer = Timer(debounceDuration, () {
      R2Log.e(readiumError);
    });
  }
}

class _ReadiumAudioSource extends StreamAudioSource {
  _ReadiumAudioSource({
    required this.getBytes,
    required this.link,
  });

  final Future<Uint8List> Function(Link) getBytes;
  final Link link;

  @override
  Future<StreamAudioResponse> request([final int? nullableStart, final int? end]) async {
    // Bad API, start should be non-nullable and default to 0 instead.
    final start = nullableStart ?? 0;
    R2Log.d('request[${link.href}] $start, $end');
    final data = await getBytes(link);
    R2Log.d('have data[${link.href}]');

    return StreamAudioResponse(
      sourceLength: data.length,
      contentLength: (end ?? data.length) - start,
      offset: start,
      stream: Stream.value(Uint8List.sublistView(data, start, end)),
      contentType: MediaType.mp3.value,
    );
  }
}

extension _ReadiumStreamExtension<T> on Stream<T> {
  Stream<T> takeUntilPlayerDisposed(final Stream<bool> playerDisposed) => TakeUntilExtension(this)
      .takeUntil(playerDisposed.where((final event) => event).distinct())
      .asBroadcastStream();
}
