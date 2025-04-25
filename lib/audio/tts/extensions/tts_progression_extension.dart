part of '../tts_audio_handler.dart';

extension TtsProgressionExtension on TtsAudioHandler {
  // This function calculates the progressions for a text block in a chapter.
  // It fetches the publication from state.
  // It calculates the progressions using the chapter index and the ratio of the block's start position plus the block offset to the chapter length.
  // It returns the progressions.
  Progressions? _calculateProgressionsT({
    required final TextBlock block,
    required final ResourceData chapter,
  }) {
    final pub = FlutterReadium.state.publication;

    return pub?.calculateProgressions(
      index: _position.chapter,
      progression: (block.beginPos + _position.blockOffset) / chapter.length,
    );
  }

  // This function handles the progress of the TTS.
  // It fetches the publication and current chapter from FlutterReadium state.
  // It fetches the locator from the publication.
  // If the current operation should be aborted, it stops the TTS and returns.
  // It calculates the start and end offsets.
  // If it is speaking a page break, it sets the word to the page break text.
  // It logs the text, start and end offsets, word, and CSS selector.
  // It sets the TTS position to the start offset.
  // It calculates the word span.
  // If the locator is not null, it calculates the progressions and updates the progress with the locator, block, and chapter.
  void _onProgress(
    final bool speakingPageBreak,
    final String? pageBreakSelector,
    final TextBlock block,
    final int offset,
    final String? pageBreakText,
    final String text,
    final int start,
    final int end,
    String word,
  ) async {
    final pub = FlutterReadium.state.publication;
    final chapter = (await _chapter)!;
    final locator = pub?.locatorFromLink(chapter.link);

    R2Log.d(_position.toString());

    if (_abortCurrent) {
      _stopSpeakingPublication();
      return;
    }

    int startOffset;
    int endOffset;

    if (speakingPageBreak) {
      startOffset = offset;
      endOffset = pageBreakText!.length + offset;
      word = pageBreakText;
    } else {
      startOffset = start + offset;
      endOffset = end + offset;
    }

    R2Log.d(
      'text=${text.truncateQuote(40)}, start=$startOffset, end=$endOffset, word="$word", '
      'cssSelector=${block.cssSelector}',
    );

    _position = _position.atBlockOffset(startOffset);
    R2Log.d('Mid');
    final wordSpan = getHighlightSpan(
      startOffset: startOffset,
      endOffset: endOffset,
      word: word,
      cssSelector: pageBreakSelector ?? block.cssSelector,
      chapter: chapter,
      block: block,
    );

    if (locator != null) {
      final progress = _calculateProgressionsT(block: block, chapter: chapter);

      setProgress(
        locator.mapLocations(
          (final locations) => locations.copyWith(
            totalProgression: progress?.totalProgression,
            progression: progress?.progression,
            cssSelector: block.cssSelector,
            domRange: wordSpan?.toDomRange(),
          ),
        ),
      );
    }
  }

  // This function handles the case where the TTS position could not be found.
  // It fetches the publication from FlutterReadium state.
  // It calculates the progressions with the chapter index and a progression of 0.
  // It updates the progress with the locator and the progressions.
  // It updates the media item.
  Future<void> _failedToFindPos(final Locator locator) async {
    final pub = FlutterReadium.state.publication;
    final progress = pub?.calculateProgressions(index: _position.chapter, progression: 0);

    await setProgress(
      locator.copyWith(
        locations: (locator.locations ?? const Locations()).copyWith(
          progression: progress?.progression,
          totalProgression: progress?.totalProgression,
        ),
      ),
    );
    return _updateMediaItem();
  }

  // This function updates the progress of the TTS.
  // It calculates the progressions.
  // If the block is an image with alt text, it updates the progress with the locator, block, and progressions, and updates the media item.
  // It calculates the word span.
  // It updates the progress with the locator, block, progressions, and word span.
  // It updates the media item.
  Future<void> _updateProgress({
    required final Locator locator,
    required final TextBlock block,
    required final chapter,
    final bool keepExactStart = false,
  }) async {
    final progressT = _calculateProgressionsT(block: block, chapter: chapter);

    // If block is an image with alt text, handle it as a special case.
    final blockText = block.text;
    if (blockText == null) {
      await setProgress(
        locator.copyWith(
          locations: (locator.locations ?? const Locations()).copyWith(
            cssSelector: block.cssSelector,
            progression: progressT?.progression,
            totalProgression: progressT?.totalProgression,
          ),
        ),
      );
      return _updateMediaItem();
    }

    // Update progress.
    final wordSpan = getHighlightSpan(
      endOffset: block.length,
      cssSelector: block.cssSelector,
      keepExactStart: keepExactStart,
      chapter: chapter,
      block: block,
    );

    await setProgress(
      locator.copyWith(
        locations: (locator.locations ?? const Locations()).copyWith(
          cssSelector: block.cssSelector,
          progression: progressT?.progression,
          totalProgression: progressT?.totalProgression,
          domRange: wordSpan?.toDomRange(),
        ),
      ),
    );

    return _updateMediaItem();
  }
}
