part of '../tts_audio_handler.dart';

extension TtsNavigationControlsExtension on TtsAudioHandler {
  // This function skips to the previous chapter in the publication.
  // It fetches the current chapter index from the TTS position.
  // It fetches the previous chapter from the chapters list.
  // It sets the TTS position to the last block of the previous chapter.
  Future<void> _skipToPreviousChapter() async {
    final chapterIndex = _position.chapter;

    final chapter = await _chapters[chapterIndex - 1];
    _position = TtsPosition(chapter: chapterIndex - 1, block: (chapter?.blocks.length ?? 1) - 1);

    R2Log.d('index: $chapterIndex');
  }

  // This function checks if the TTS is near the start of the current chapter.
  // If it is, it skips to the previous chapter.
  // Otherwise, it sets the TTS position to the previous block or chapter.
  Future<void> _setPreviousIfNearStart() async {
    if (await _isNearStartOfChapter()) {
      return _skipToPreviousChapter();
    }

    await _setPrevious();
  }

  // This function sets the TTS position to the previous block or chapter.
  // It fetches the current chapter index and block index from the TTS position.
  // It logs the chapter index and block index.
  // If the block index is greater than 0, it skips to the start of the chapter.
  // If the block index is 0 and the chapter index is greater than 0, it skips to the previous chapter.
  // If the block index and chapter index are both 0, it resets the TTS position.
  Future<void> _setPrevious() async {
    final chapterIndex = _position.chapter;
    final blockIndex = _position.block;

    R2Log.d('index: $chapterIndex, blockIndex: $blockIndex');
    if (blockIndex > 0) {
      final bIndex = blockIndex - 1;
      R2Log.d('Set block to $bIndex');

      _position = _position.atBlock(bIndex);
    } else if (chapterIndex > 0) {
      await _skipToPreviousChapter();
    } else {
      _position = const TtsPosition();
    }
  }

  // This function pauses the TTS, runs a function, and then resumes the TTS.
  // If the TTS is playing, it stops the TTS, runs the function, resumes the TTS, and returns the result of the function.
  // If the TTS is not playing, runs the function, and returns the result of the function.
  Future<T> _doWhilePaused<T>(final Future<T> Function() f) async {
    if (_playing && FlutterReadium.state.playing) {
      R2Log.d('Pause playing');
      await _stopSpeakingPublication();
      R2Log.d('Run function');
      final ret = await f();

      R2Log.d('Run done - continue playing');
      _speak();
      R2Log.d('Done');
      return ret;
    } else {
      R2Log.d('Run function');
      return f();
    }
  }
}
