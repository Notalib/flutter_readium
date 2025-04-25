part of '../tts_audio_handler.dart';

extension TtsHighlightExtension on TtsAudioHandler {
  // This function observes the highlight mode of the Text-to-Speech (TTS).
  // It fetches the highlight mode from FlutterReadium.
  // It waits for the highlight mode to change.
  // If the TTS is playing, it continues to the next iteration.
  // It fetches the current audio locator.
  // If the audio locator is not null, it nudges the position and updates the progress.
  // If an error occurs, it logs the error.
  Future<void> _observeHighlightMode() async {
    R2Log.d('Observing');

    final highlightMode = FlutterReadium.stateStream.highlightModeUntilReaderClosed;
    await for (final mode in highlightMode) {
      final state = FlutterReadium.state;

      R2Log.d('Changed - $mode');
      try {
        if (state.playing) {
          continue;
        }

        final locator = FlutterReadium.state.audioLocator;

        if (locator != null) {
          await _nudgePositionAndUpdateProgress(
            audioLocator: locator,
          );
        }
      } on Object catch (error) {
        R2Log.e(error, data: mode);
      }
    }

    R2Log.d('Done');
  }

  // This function gets the highlight span for a specific block of text.
  // If the TTS is in word highlight mode, it selects either the whole word at the cursor or the remaining part of the word at the cursor, depending on keepExactStart.
  // It calculates the start and end of the word.
  // If the block text is null, it returns a ReadiumElement with the link and CSS selector of the chapter.
  // Otherwise, it returns a ReadiumElement with the link, start, end, text, and CSS selector of the chapter.
  ReadiumElement? getHighlightSpan({
    required final String cssSelector,
    required final int endOffset,
    required final ResourceData chapter,
    required final TextBlock block,
    final String? word,
    final bool keepExactStart = false,
    final ReadiumElement? element,
    final int startOffset = 0,
  }) {
    final state = FlutterReadium.state;

    final blockText = block.text;

    if (state.isWordHighlightMode && !_currentVoiceIsAndroidNetwork) {
      // Select either the whole word at the cursor or the remaining part of the word at the cursor,
      // depending on keepExactStart.
      final startOfWord = _position.blockOffset;
      var endOfWord = _position.blockOffset;
      if (blockText != null) {
        if (!keepExactStart) {
          var offset = _position.blockOffset;
          while (offset > 0 && blockText[offset - 1].trimRight().isNotEmpty) {
            --offset;
          }
          _position = _position.atBlockOffset(offset);
        }
        while (endOfWord < endOffset && blockText[endOfWord].trimRight().isNotEmpty) {
          ++endOfWord;
        }
      }

      return blockText == null
          ? ReadiumElement(link: chapter.link, cssSelector: block.cssSelector)
          : ReadiumElement(
              link: chapter.link,
              start: startOfWord,
              end: endOfWord,
              text: word ?? blockText.substring(startOfWord, endOfWord),
              cssSelector: cssSelector,
            );
    } else if (state.isSentenceHighlightMode && !_currentVoiceIsAndroidNetwork) {
      List<RegExpMatch> sentences;

      // for more accurate sentence selection we should use a nlp library, however I have been unable to find a good one for flutter, where it does not require a lot of setup and unnecessary extra work for this simple task.
      // this simple will not work when there is mr. mrs. dr. etc. in the text
      // it will also not work when there is a time like 12.20 in the text.
      final sentenceRegex = RegExp(r'\S[^.!?]*[.!?]', multiLine: true);

      if (blockText != null) {
        sentences = sentenceRegex.allMatches(blockText).toList();
      } else {
        return ReadiumElement(link: chapter.link, cssSelector: block.cssSelector);
      }

      var sentenceStart = startOffset;
      var sentenceEnd = endOffset;

      for (final match in sentences) {
        if (match.start <= startOffset && match.end >= endOffset) {
          sentenceStart = match.start;
          sentenceEnd = match.end;
          break;
        }
      }

      return ReadiumElement(
        link: chapter.link,
        start: sentenceStart,
        end: sentenceEnd,
        text: blockText.substring(sentenceStart, sentenceEnd),
        cssSelector: cssSelector,
      );
    }

    return blockText == null
        ? null
        : ReadiumElement(
            link: chapter.link,
            start: 0,
            end: blockText.length,
            text: blockText,
            cssSelector: cssSelector,
          );
  }
}
