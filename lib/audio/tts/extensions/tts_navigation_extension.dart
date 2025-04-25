part of '../tts_audio_handler.dart';

extension TtsNavigationExtension on TtsAudioHandler {
  // This function checks if the TTS is near the start of the current chapter.
  // It fetches the current block from the TTS position.
  // It fetches the start offset of the block.
  // It returns true if the offset is less than 70, indicating that the TTS is near the start of the chapter.
  Future<bool> _isNearStartOfChapter() async {
    final block = await _block;
    final offset = block?.beginPos ?? 0;

    R2Log.d('$offset');

    return offset < 70;
  }

  // This function normalizes the TTS position if it is at the end of the book.
  // It takes the TTS position as a parameter.
  // If the chapter index of the position is less than the number of chapters, it returns the position.
  // It fetches the last chapter.
  // If the last chapter is null, it returns a new TTS position with default values.
  // It returns a new TTS position with the chapter index set to the last chapter index and the block index set to the number of blocks in the last chapter.
  Future<TtsPosition> _fixPastBookEnd(final TtsPosition position) async {
    if (position.chapter < _chapters.length) {
      return position;
    }

    final chapter = await _chapters.lastOrNull;

    if (chapter == null) {
      return const TtsPosition();
    }

    return TtsPosition(chapter: _chapters.length - 1, block: chapter.blocks.length);
  }

  // This function checks if the TTS is at the end of the current chapter.
  // It fetches the blocks of the current chapter.
  // It checks if the block index of the TTS position is greater than or equal to the number of blocks.
  // It returns true if the TTS is at the end of the chapter.
  Future<bool> _atEndOfChapter() async {
    final b = await _blocks;

    final isEnd = b == null || _position.block >= b.length;

    R2Log.d('$isEnd');

    return isEnd;
  }

  // This function checks if the TTS is at the end of the publication.
  // It initializes a flag to false.
  // If the chapter index of the TTS position is the last chapter index, it checks if the TTS is at the end of the chapter and sets the flag to the result.
  // If the flag is true, it broadcasts the state with the processing state set to completed.
  // It returns the flag.
  Future<bool> _atEndOfPublication() async {
    var atEnd = false;
    if (_position.chapter == _chapters.length - 1) {
      atEnd = await _atEndOfChapter();
    }

    if (atEnd) {
      _broadcastState(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.completed,
        ),
      );
    }

    R2Log.d('$atEnd');

    return atEnd;
  }

  // This function fetches the chapter with a specific href.
  // It finds the index of the href in the hrefs list.
  // If the index is -1, it sets the chapter to null.
  // Otherwise, it fetches the chapter at the index.
  // It returns the chapter.
  Future<ResourceData?>? _chapterWithHref(final String href) {
    R2Log.d(href);
    final index = _hrefs.indexOf(href);
    final chapter = index == -1 ? null : _chapters[index];

    return chapter;
  }
}
