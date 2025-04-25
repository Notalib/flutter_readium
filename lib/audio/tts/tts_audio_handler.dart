import 'dart:async';
import 'dart:io' hide Link;
import 'dart:math';

import 'package:flutter_tts/flutter_tts.dart';

import '../../_index.dart';
import 'split_resource.dart';
import 'tts_position.dart';
import 'default_voices.dart';

part 'extensions/tts_highlight_extension.dart';
part 'extensions/tts_navigation_controls_extension.dart';
part 'extensions/tts_navigation_extension.dart';
part 'extensions/tts_position_extension.dart';
part 'extensions/tts_progression_extension.dart';
part 'extensions/tts_speak_extension.dart';
part 'extensions/tts_voice_extension.dart';

class TtsAudioHandler extends ReadiumAudioHandler {
  FlutterTts? _tts;

  var _abortCurrent = false;
  var _playing = false;
  Completer<void>? _speakingCompleter;
  Locator? _lastTextPosition;
  String? _lastLang;

  /// Contains all TTS voiced installed on the device.
  Iterable<ReadiumTtsVoice>? _voices;

  // There is a problem with highlight one word and android tts network voices.
  bool _currentVoiceIsAndroidNetwork = false;

  late List<String> _hrefs;
  late List<Future<ResourceData?>> _chapters;

  var _position = const TtsPosition();

  Future<ResourceData?> get _chapter => _chapters[_position.chapter];
  Future<List<TextBlock>?> get _blocks => _chapter.then((final c) => c?.blocks);
  Future<TextBlock?> get _block => _blocks
      .then((final b) => b != null && _position.block < b.length ? b[_position.block] : null);

  /// Is the reading order and toc the same
  late bool _tocIsReadingOrder;

  // This function initializes the Text-to-Speech (TTS) functionality.
  // If the TTS is already initialized, it does nothing.
  // If the platform is iOS, it sets the shared instance and audio category for the TTS.
  // It also sets the speed of the TTS to the current playback rate.
  Future<void> _initTts() async {
    if (_tts != null) {
      return;
    }

    _tts = FlutterTts();
    if (Platform.isIOS) {
      await _tts?.setSharedInstance(true);
      await _tts?.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ]);
    }

    // Important to set the playbackRate on init to make sure the rate is set when tts starts the
    // playback.
    setSpeed(FlutterReadium.state.playbackRate);
  }

  // This function is called when the publication is updated.
  // It fetches the current state and publication from FlutterReadium.
  // If no publication is set, it logs a message and returns.
  // It logs the publication and initial locator.
  // It fetches the reading order of the publication and splits the resources into chapters.
  // It initializes the TTS position.
  // If TTS is not enabled, it logs a message and returns.
  // It updates the media item and broadcasts the state.
  // It sets the queue value to the reading order of the publication.
  // It initializes the TTS and observes the highlight mode.
  @override
  Future<void> publicationUpdated() async {
    final state = FlutterReadium.state;
    final publication = state.publication;
    final initialLocator = state.currentLocator;

    if (publication == null) {
      R2Log.d('No Publication is set');

      return;
    }

    R2Log.d('publication:    ${publication.identifier}');
    R2Log.d('initialLocator: $initialLocator');

    // Post-fetch resources.
    final readingOrder = publication.readingOrder;
    _hrefs = readingOrder.map((final link) => link.href).toList();
    _chapters = readingOrder
        .mapIndexed(
          (final index, final link) => Future(() async {
            try {
              final html = await ReadiumPublicationChannel.getString(link);
              return splitResource(link, XmlDocument.parse(html), index, publication);
            } on Object catch (e) {
              R2Log.e(
                e,
                data: {
                  'index': index,
                  'link': link,
                },
              );
            }
          }),
        )
        .toList();

    final toc = publication.toc;

    final flattenedToc = toc?.toFlattenedToc().toList();

    _tocIsReadingOrder = flattenedToc == null || flattenedToc.length == readingOrder.length;

    _position = const TtsPosition();

    if (!state.ttsEnabled) {
      R2Log.d('TTS not enabled - void');

      return;
    }

    _updateMediaItem();
    _broadcastState(
      playbackState.value.copyWith(
        updatePosition: Duration.zero,
        playing: false,
      ),
    );

    final coverUri = FlutterReadium.state.pubCoverUri;

    queue.value = readingOrder
        .mapIndexed(
          (final index, final link) => ttsMediaItem(
            publication: publication,
            index: index,
            link: link,
            artUri: coverUri,
          ),
        )
        .toList();

    await _initTts();

    _observeHighlightMode();

    R2Log.d('Done');
  }

  // This function sets the progress of the TTS.
  // It calculates the chapter offset and duration.
  // It broadcasts the state with the updated position.
  // It calls the superclass's setProgress method with the locator.
  @override
  Future<void> setProgress(final Locator locator) async {
    R2Log.d('$locator');
    _lastTextPosition = locator;
    final block = await _block;
    final chapterOffset = (block?.beginPos ?? 0) + _position.blockOffset;
    final duration = durationPerCharacter * chapterOffset;
    _broadcastState(playbackState.value.copyWith(updatePosition: duration));
    return super.setProgress(locator);
  }

  // This function retrieves the XML document of a specific resource.
  // It fetches the resource associated with the href.
  // It returns the XML document of the resource.
  @override
  Future<XmlDocument?> getDocument(final String href) async {
    R2Log.d(href);

    final resource = await _chapterWithHref(href);

    return resource?.document;
  }

  // This function handles the click event on the media buttons.
  // Depending on the button that was clicked, it performs different actions:
  // - If the media button was clicked, it calls the superclass's click method.
  // - If the next button was clicked, it skips to the next paragraph.
  // - If the previous button was clicked, it skips to the previous paragraph.
  @override
  Future<void> click([final MediaButton button = MediaButton.media]) async {
    R2Log.d('Click - $button');

    switch (button) {
      case MediaButton.media:
        super.click(button);
        break;
      case MediaButton.next:
        await skipToNextParagraph();
        break;
      case MediaButton.previous:
        await skipToPreviousParagraph();
        break;
    }
  }

  // This function starts the Text-to-Speech (TTS) playback.
  // It fetches the current state from FlutterReadium.
  // If no publication is set or if TTS is not enabled, it logs a message and prevents the playback.
  // It initializes the TTS and sets the volume to 1.0.
  // It broadcasts the state with the updated processing state and playing status.
  // It sets the speed of the TTS to the current playback rate.
  // If the TTS is not already playing, it starts the TTS.
  // It calls the superclass's play method.
  @override
  Future<void> play() async {
    R2Log.d('play');

    final state = FlutterReadium.state;

    if (!state.hasPub) {
      R2Log.d('No publication is set - prevent play');

      return;
    }

    if (!state.ttsEnabled) {
      R2Log.d('TTS not enabled - prevent play');

      return;
    }

    await _initTts();
    _tts?.setVolume(1.0);

    _broadcastState(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.ready,
        playing: true,
      ),
    );
    setSpeed(FlutterReadium.state.playbackRate);

    if (!_playing) {
      _speak();
    }

    super.play();
  }

  // This function pauses the Text-to-Speech (TTS) playback.
  // It broadcasts the state with the updated processing state and playing status.
  // It calls the superclass's pause method.
  // It stops the TTS from speaking the publication.
  @override
  Future<void> pause() async {
    R2Log.d('pause');
    // Pause function works fine on android, but due to the way we handle progression using pause on ios can cause an error.
    // await _tts.pause();
    // _playing = false;

    _broadcastState(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.ready,
        playing: false,
      ),
    );

    super.pause();

    await _stopSpeakingPublication();
  }

  // This function creates a fade effect for pause.
  // It gradually reduces the volume of the TTS from 100 to 0 in steps of 10 every 200 milliseconds.
  // It then calls the pause method.
  @override
  Future<void> pauseFade() async {
    R2Log.d('pause with fade');

    var volume = 100;

    while (volume >= 0) {
      await Future.delayed(const Duration(milliseconds: 200));

      volume = volume - 10;
      _tts?.setVolume(volume / 100);
    }

    return pause();
  }

  // This function stops the Text-to-Speech (TTS) playback.
  // It updates the playback state to idle and not playing.
  // It calls the superclass's stop method.
  @override
  Future<void> stop() async {
    R2Log.d('Stop');
    // Signal the speech to stop
    await _stopSpeakingPublication();
    // Wait for the speech to stop
    //await _completer.future;

    playbackState.value = playbackState.value.copyWith(
      controls: const [],
      processingState: AudioProcessingState.idle,
      playing: false,
    );

    // Shut down this task
    return super.stop();
  }

  // This function cleans up the TTS.
  // It calls the superclass's cleanup method.
  // It stops the TTS.
  // It sets the TTS to null.
  // It re-initializes the TTS.
  @override
  Future<void> cleanup() async {
    R2Log.d('stop and re-init tts');

    super.cleanup();

    await stop();

    _tts = null;

    await _initTts();
  }

  // This function sets the speed of the Text-to-Speech (TTS).
  // It logs the speed.
  // It adjusts the speed to a value between 0.0 and 1.0.
  // It sets the speech rate of the TTS to the adjusted speed while the TTS is paused.
  @override
  Future<void> setSpeed(final double speed) async {
    R2Log.d('speed: $speed');

    // Not exactly right, but map 0 → 0, 1 → ½, ∞ → 1.
    // TODO: Figure out exactly how setSpeechRate affects the speech rate. Maybe platform dependent.
    final rate = (speed / (1 + speed)).clamp(0.0, 1.0);
    R2Log.d('Adjusted TTS rate: $rate');
    return _doWhilePaused(() async => _tts?.setSpeechRate(rate));
  }

  // This function handles the go action with a locator.
  // If TTS is not enabled, it logs a message and sets the progress to the locator.
  // It fetches the chapter associated with the locator.
  // If the chapter is not found or if no data is fetched for the chapter, it logs a message and returns.
  // It fetches the dom range, progression, and css selector from the locator.
  // Depending on the values of the dom range, progression, and css selector, it performs different actions.
  // It seeks to the position in the chapter associated with the locator.
  // TODO: if it cannot find the position in the chapter it currently restarts the publication, a quick fix would be restart the chapter, but a better solution would be to find a better way to find the position in the chapter.
  @override
  Future<void> go(final Locator locator) async {
    if (!FlutterReadium.state.ttsEnabled) {
      R2Log.d('TTS not enabled - no need to handle locator');

      setProgress(locator);

      return;
    }

    R2Log.d('$locator');
    final chapterIndex = _hrefs.indexOf(locator.href);
    if (chapterIndex == -1) {
      R2Log.e(
        'Unknown chapter',
        data: locator,
      );
      return;
    }
    final chapter = await _chapters[chapterIndex];
    if (chapter == null) {
      R2Log.e(
        'No data fetched for chapter',
        data: locator,
      );
      return;
    }
    final domRange = locator.locations?.domRange;
    final progression = locator.locations?.progression;
    final cssSelector = locator.locations?.cssSelector;

    if (domRange == null && cssSelector != null) {
      R2Log.d('Null domRange, try to seek to cssSelector: ${locator.href} $cssSelector');

      final block =
          chapter.blocks.firstWhereOrNull((final block) => block.cssSelector == cssSelector);

      if (block != null) {
        return _seekToPos(chapterIndex, block.beginPos, exact: true);
      }

      R2Log.d('Null domRange, block not found by cssSelector: ${locator.href} $cssSelector');

      // if no block is found, and toc and readingOrder are not the same, find and seek to first block in toc from fragments.
      if (!_tocIsReadingOrder) {
        final tocFragment = locator.locations?.tocFragment;
        final tocBlock =
            chapter.blocks.firstWhereOrNull((final block) => block.cssSelector == '#$tocFragment');

        if (tocBlock != null) {
          return _seekToPos(chapterIndex, tocBlock.beginPos, exact: true);
        }
      }

      // if toc and reading order are the same or no tocBlock from fragments seek to start of chapter
      return _seekToPos(chapterIndex, 0, exact: true);
    }

    if (domRange == null && progression != null) {
      R2Log.d('Null domRange, seek to progression: ${locator.href} $progression');

      return setProgress(locator);
    }

    if (domRange == null) {
      R2Log.d('Null domRange, seek to start: ${locator.href}');
      return _seekToPos(chapterIndex, 0, exact: true);
    }
    final pos = chapter.domPosition(domRange.start)?.local();
    if (pos == null) {
      R2Log.e(
        'Bad boundary',
        data: locator,
      );

      return;
    }
    final endPos = domRange.end == null ? null : chapter.domPosition(domRange.end!);
    final lastTextRange = _lastTextPosition?.locations?.domRange;
    if (endPos != null &&
        lastTextRange != null &&
        locator.locations?.position == _position.chapter) {
      final lastWordPos = chapter.domPosition(lastTextRange.start);
      final lastWordEndPos = chapter.domPosition(lastTextRange.end ?? lastTextRange.start);
      if (lastWordPos != null &&
          lastWordEndPos != null &&
          pos.compareTo(lastWordEndPos)! < 0 &&
          endPos.compareTo(lastWordPos)! > 0) {
        R2Log.d('Last selected word already on current page, abort seek.');
        return;
      }
    }

    for (final block in chapter.blocks) {
      final blockPos = pos.offsetInAncestor(block.element);
      if (blockPos != null) {
        final positionInBlock = blockPos.charOffset;
        final positionInChapter = block.beginPos + positionInBlock;
        R2Log.d(
          'positionInBlock=$positionInBlock, positionInChapter=$positionInChapter, '
          '${block.textOrAlt.truncateQuote(40, start: positionInBlock)}',
        );
        return _seekToPos(chapterIndex, positionInChapter, exact: true);
      }
    }

    R2Log.e(
      'Block not found.',
      data: locator,
    );

    return;
  }

  // This function seeks to a specific position in the chapter.
  // It fetches the current chapter.
  // If no chapter is found, it logs a message and returns.
  // It calculates the position in the resource and seeks to that position.
  @override
  Future<void> seek(final Duration position) async {
    R2Log.d('$position');
    final chapter = await _chapter;
    if (chapter == null) {
      R2Log.e(
        'Missing chapter',
        data: position,
      );
      return;
    }
    final positionInResource = (position / chapter.duration * chapter.length).round();
    _seekToPos(_position.chapter, positionInResource);
  }

  // This function skips to the next chapter in the publication.
  // It pauses the TTS, moves the position to the next chapter, and updates the progress.
  @override
  Future<void> skipToNext() async {
    R2Log.d('Skip to next chapter');

    return _doWhilePaused(() async {
      _position = await _fixPastBookEnd(_position.nextChapter());
      return _nudgePositionAndUpdateProgress();
    });
  }

  // This function skips to the previous chapter in the publication.
  // It pauses the TTS, moves the position to the start of the current chapter or the previous, and updates the progress.
  @override
  Future<void> skipToPrevious() async {
    R2Log.d('Skip to prev chapter');

    return _doWhilePaused(() async {
      await _setPreviousIfNearStart();
      _position = TtsPosition(chapter: _position.chapter);
      return _nudgePositionAndUpdateProgress();
    });
  }

  // This function skips to the next paragraph (block) in the publication.
  // It pauses the TTS, moves the position to the next block, and updates the progress.
  // If the next block is a page break and the TTS is not set to speak the physical page index, it skips to the next paragraph.
  @override
  Future<void> skipToNextParagraph() async {
    R2Log.d('Skip to next segment');

    return _doWhilePaused(() async {
      final blocks = await _blocks;
      if (_position.block >= (blocks?.length ?? 0) - 1) {
        _position = await _fixPastBookEnd(_position.nextChapter());
      } else {
        _position = _position.nextBlock();
      }

      if ((await _block)?.element.isPageBreak == true &&
          !FlutterReadium.state.ttsSpeakPhysicalPageIndex) {
        return skipToNextParagraph();
      }

      return _nudgePositionAndUpdateProgress();
    });
  }

  // This function skips to the previous paragraph (block) in the publication.
  // It pauses the TTS, moves the position to the previous block, and updates the progress.
  // If the previous block is a page break and the TTS is not set to speak the physical page index, it skips to the previous paragraph.
  @override
  Future<void> skipToPreviousParagraph() async {
    R2Log.d('Skip to prev segment');

    return _doWhilePaused(() async {
      await _setPrevious();

      if ((await _block)?.element.isPageBreak == true &&
          !FlutterReadium.state.ttsSpeakPhysicalPageIndex) {
        return skipToPreviousParagraph();
      }

      return _nudgePositionAndUpdateProgress();
    });
  }

  // This function gets the TTS voices for the publication.
  // It fetches the languages of the publication.
  // If no languages are set for the publication, it throws an exception.
  // It fetches the available voices.
  // It filters the voices by the languages of the publication.
  // If no voices are found for the languages of the publication, it tries to find voices for the fallback languages.
  // If no voices are found for the fallback languages, it throws an exception.
  // It returns the voices for the languages of the publication.
  @override
  Future<List<ReadiumTtsVoice>> getTtsVoices({final List<String>? fallbackLang}) async {
    final pubLangs = FlutterReadium.state.pubLangs;

    if (pubLangs == null) {
      throw const ReadiumException('Publication has no language metadata');
    }

    final voices = await _getVoices();

    var pubVoices = voices.where((final voice) => pubLangs.contains(voice.langCode)).toList();

    if (pubVoices.isEmpty) {
      if (fallbackLang != null) {
        pubVoices = voices.where((final voice) => fallbackLang.contains(voice.langCode)).toList();

        if (pubVoices.isNotEmpty) {
          return pubVoices;
        }
      }
      final supportedLanguages = voices.map((final voice) => voice.langCode).toSet();
      throw ReadiumException(
        'No matching voices found - ttsLang: $pubLangs. Device supported tts languages: $supportedLanguages',
      );
    }

    return pubVoices;
  }

  // This function sets the TTS voice for the publication.
  // It initializes the TTS if it is not already initialized.
  // It sets the voice of the TTS to the selected voice.
  @override
  Future<void> setTtsVoice(final ReadiumTtsVoice selectedVoice) async {
    if (_tts == null) {
      await _initTts();
    }

    await _tts?.setVoice(selectedVoice.toJson().cast());

    if (selectedVoice.androidIsLocal != false) {
      _currentVoiceIsAndroidNetwork = false;
    } else {
      _currentVoiceIsAndroidNetwork = true;
    }
  }

  // This function updates the media item of the TTS.
  // It fetches the current chapter.
  // It logs the length and duration of the chapter.
  // If the chapter is not null, it sets the media item of the TTS to the media item of the chapter.
  Future<void> _updateMediaItem() async {
    final chapter = await _chapter;
    R2Log.d('Position ${chapter?.length}/${chapter?.duration}');
    if (chapter != null) {
      mediaItem.value = chapter.mediaItem;
    }
  }

  /// Broadcast current state.
  // This function fetches the TTS enabled state from FlutterReadium.
  // If TTS is not enabled, it sets the playback state to idle and not playing.
  // It checks if the platform is iOS.
  // It sets the controls of the playback state depending on the playing status and the platform.
  // It sets the system actions of the playback state to seek, seek forward, and seek backward.
  // It sets the compact action indices of the playback state to 0, 1, and 2.
  // If the playback state has an error, it resets the error state.
  void _broadcastState(final PlaybackState state) {
    final ttsEnabled = FlutterReadium.state.ttsEnabled;

    if (!ttsEnabled) {
      playbackState.value = state.copyWith(
        controls: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
        systemActions: const {},
        androidCompactActionIndices: null,
        errorCode: null,
        errorMessage: null,
      );

      return;
    }

    final isIOS = Platform.isIOS;

    playbackState.value = state.copyWith(
      // TODO: look into why on ios the skipToPrevious and skipToNext are for paragraphs while on android they are for chapters.
      controls: [
        MediaControl.skipToPrevious,

        if (state.playing) MediaControl.pause else MediaControl.play,

        /// We have to add both play/pause controls on iOS to make sure the button does not get
        /// disabled on toggle.
        if (isIOS && state.playing) MediaControl.play,
        if (isIOS && !state.playing) MediaControl.pause,

        MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.seek,
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
    }
  }
}
