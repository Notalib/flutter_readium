part of '../tts_audio_handler.dart';

extension TtsPositionExtension on TtsAudioHandler {
  // This function scrolls backwards to the start of a word and updates the progress to that word.
  // It fetches the state and publication from FlutterReadium.
  // It fetches the current chapter.
  // If the chapter or publication is null, it logs an error and returns.
  // It fetches the locator from the publication or the audioLocator.
  // If the locator is null, it logs an error and returns.
  // If the chapter is empty, it logs a message and returns.
  // It fetches the current block.
  // If the block is null, it sets the TTS position to the previous block or chapter and fetches the block again.
  // If the block is still null, it logs a message and returns.
  // It calculates the offset of the block.
  // It sets the TTS position to the offset.
  // It updates the progress with the locator, block, and chapter.
  Future<void> _nudgePositionAndUpdateProgress({
    final bool keepExactStart = false,
    final Locator? audioLocator,
  }) async {
    R2Log.d('keepExactStart: $keepExactStart');
    final state = FlutterReadium.state;
    final pub = state.publication;
    final chapter = await _chapter;

    if (chapter == null || pub == null) {
      R2Log.e(
        'Chapter data or pub not set',
        data: {'chapter': chapter, 'publication': pub},
      );

      return;
    }

    final locator = audioLocator ?? pub.locatorFromLink(chapter.link, typeOverride: MediaType.html);

    if (locator == null) {
      R2Log.e(
        'Could not convert chapter link to locator',
        data: {'link': chapter.link},
      );

      return;
    }

    // If we're completely lost, or the chapter is empty. Shouldn't get here anymore, since we add a
    // dummy block in empty chapters.
    if (chapter.blocks.isEmpty) {
      R2Log.d('Return, chapter is ${chapter.link.href}');

      return _failedToFindPos(locator);
    }

    // If block is null, we're at the end of a chapter. If so, start by navigating to the last non-
    // whitespace character of the chapter.
    var block = await _block;
    if (block == null) {
      await _setPrevious();
      block = await _block;
      if (block == null) {
        R2Log.d('Return, no non-null block?!');
        return _failedToFindPos(locator);
      }
      final blockText = block.text;
      if (blockText != null) {
        var offset = block.length;
        while (offset > 0) {
          --offset;

          try {
            if (blockText[offset - 1].trimRight().isEmpty) {
              break;
            }
          } on Object catch (_) {
            break;
          }
        }
        _position = _position.atBlockOffset(offset);
      }
    }

    await _updateProgress(locator: locator, block: block, chapter: chapter);
  }

  // This function seeks to a specific position in the publication.
  // It fetches the chapter at the chapter index.
  // If the chapter is null, it logs an error and returns.
  // It pauses the TTS, sets the TTS position to the position in chapter, and resumes the TTS.
  Future<void> _seekToPos(
    final int chapterIndex,
    final int positionInChapter, {
    final bool exact = false,
  }) async {
    R2Log.d('chapterIndex: $chapterIndex positionInChapter: $positionInChapter exact: $exact');

    final chapter = await _chapters[chapterIndex];
    if (chapter == null) {
      R2Log.e('Missing chapter data $chapterIndex');
      return;
    }
    return _doWhilePaused(() async {
      // Set _blockIndex and _positionInBlock such that position == _position.
      final blocks = chapter.blocks;
      final blockIndex =
          _binarySearchWhere<TextBlock>(blocks, (final block) => positionInChapter < block.endPos);
      final offset =
          blockIndex < blocks.length ? max(positionInChapter - blocks[blockIndex].beginPos, 0) : 0;
      _position = TtsPosition(chapter: chapterIndex, block: blockIndex, blockOffset: offset);
      await _nudgePositionAndUpdateProgress(keepExactStart: exact);
      return;
    });
  }

  /// Standard upper bound algorithm (binary search), somehow seems missing from the `collection`
  /// package.
  // int _upperBound<E extends Comparable<Object?>>(List<E> sortedList, E value) =>
  //     lowerBound<E>(sortedList, value,
  //         compare: (e, v) => e.compareTo(v) <= 0 ? -1 : 0);

  /// Returns the index of the first element testing true, assuming all elements testing true come
  /// after all elements testing false. Returns sortedList.length if all elements test false.
  int _binarySearchWhere<E>(final List<E> sortedList, final bool Function(E) test) {
    var lower = 0;
    var upper = sortedList.length;
    while (lower != upper) {
      final mid = (lower + upper) ~/ 2;
      if (test(sortedList[mid])) {
        upper = mid;
      } else {
        lower = mid + 1;
      }
    }
    return lower;
  }
}
