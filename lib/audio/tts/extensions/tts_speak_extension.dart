part of '../tts_audio_handler.dart';

extension TtsSpeakExtension on TtsAudioHandler {
  // This function starts the Text-to-Speech (TTS) process.
  // It initializes the abort flag and the speaking completer.
  // It checks if it's at the end of the publication.
  // If it is, it resets the TTS position.
  // It enters a loop where it speaks each block until it reaches the end of the publication or the process is aborted.
  // If it's at the end of a chapter, it moves to the next chapter and continues the loop.
  // It speaks the current block.
  // If the process is aborted, it logs a message, completes the speaking completer, and returns.
  // It moves to the next block.
  // If an error occurs, it logs the error, completes the speaking completer, and logs a message.
  Future<void> _speak() async {
    _abortCurrent = false;
    _speakingCompleter = Completer<void>();

    try {
      R2Log.d('Started');
      if (await _atEndOfPublication()) {
        _position = const TtsPosition();
      }
      while (!await _atEndOfPublication() && !_abortCurrent) {
        if (await _atEndOfChapter()) {
          _position = _position.nextChapter();
          continue;
        }
        await _speakBlock();
        if (_abortCurrent) {
          R2Log.d('Aborted');
          _speakingCompleter?.safeComplete();
          return;
        }
        _position = _position.nextBlock();
      }

      _speakingCompleter?.safeComplete();
    } on Object catch (e) {
      R2Log.e(e, data: _position);

      _speakingCompleter?.safeComplete();
    }
    R2Log.d('Done');
  }

  // This function speaks a block of text.
  // It initializes several variables including whether it's speaking a page break, the page break text, and the page break selector.
  // It fetches the current block.
  // It sets the block offset to the TTS position's block offset.
  // If the process is aborted, it logs a message and returns.
  // It updates the current media item and enables media buttons on Android.
  // If the process is aborted, it logs a message and returns.
  // It sets up the TTS listeners.
  // It starts speaking the text from the current offset.
  // It checks if the language has changed, and if it has, it sets the TTS language or voice.
  // If the block is a page break, it speaks the page break text and updates the offset.
  // If the block contains a page break, it speaks each child of the block and updates the offset.
  // If the block is not a page break and does not contain a page break, it speaks the text.
  // It resets the page break variables and logs a message.
  Future<void> _speakBlock() async {
    R2Log.d('position = $_position');

    var speakingPageBreak = false;
    String? pageBreakText;
    String? pageBreakSelector;

    final block = (await _block)!;

    // If this is wrong it can cause an error that makes it impossible to start speaking again.
    // In paragraps with pagebreaks, when resuming after pause it restarts from the beginning of the paragraph, rather than where it was paused, however _position.blockOffset is not reset, so if one pauses many times within the same paragraph, the offset will be greater than the length of the paragraph, causing the error.
    // if using tts.pause() and pausing multiple times in the same paragraph/block, it will cause the same error as above, but only on ios.
    // TODO: look into this further.
    var offset = _position.blockOffset;

    if (_abortCurrent) {
      R2Log.d('AbortCurrent-A');
      return;
    }

    // Update current media item, to ensure its chapter is correct.
    await _updateMediaItem();

    if (_abortCurrent) {
      R2Log.d('AbortCurrent-B');
      return;
    }

    // Setup listeners.
    var completer = Completer<void>();
    _tts!
      ..setCompletionHandler(() {
        R2Log.d('TTS complete');
        completer.safeComplete();
      })
      ..setCancelHandler(() {
        R2Log.d('TTS cancel');
        completer.safeComplete();
      })
      ..setErrorHandler((final message) {
        R2Log.e(message);
        completer.safeComplete();
      })
      ..setProgressHandler((final text, final start, final end, final word) {
        _onProgress(
          speakingPageBreak,
          pageBreakSelector,
          block,
          offset,
          pageBreakText,
          block.textOrAlt,
          start,
          end,
          word,
        );
      });

    // Speak!
    _playing = true;
    final text = block.speakableText.substring(offset);
    final truncatedText = text.truncateQuote(100);

    final closestLang = block.closestLang;
    final currentVoices = FlutterReadium.state.currentTtsVoices;

    if (closestLang != _lastLang) {
      await _setLanguageOrVoice(closestLang, currentVoices);
    }

    R2Log.d('About to speak $truncatedText');

    final speakPhysicalIndex = FlutterReadium.state.ttsSpeakPhysicalPageIndex;

    if (block.element.isPageBreak) {
      pageBreakText = block.element.domText();
      if (speakPhysicalIndex) {
        speakingPageBreak = true;
        pageBreakSelector = block.element.idCssSelector;

        await _tts?.speak(text);
        await completer.future;
        completer = Completer<void>();
      }
      offset += pageBreakText.length;
    } else if (block.element.hasPageBreak) {
      // TODO: find a better way to handle this than using for loops. - so far all solutions have caused more problems than they solved.
      /// It causes the following errors:
      /// when resuming after pause it restarts from the beginning of the paragraph, rather than where it was paused. Due to the way we handle progression, it is possible to provoke a bug with this as well.
      /// _stopSpeakingPublication is called multiple times when tts gets paused, which leads to minor sound glitches, not a big deal but should be fixed.
      for (final blockChild in block.element.children) {
        if (blockChild.isTextNode) {
          speakingPageBreak = false;
          pageBreakSelector = null;
          pageBreakText = null;

          final childText = blockChild.domText();
          await _tts?.speak(childText);

          await completer.future;
          completer = Completer<void>();

          offset += blockChild.domText().length;
        } else if (blockChild.isPageBreak) {
          pageBreakSelector = null;
          pageBreakText = blockChild.domText();
          if (speakPhysicalIndex) {
            speakingPageBreak = true;
            final appLang = FlutterReadium.state.appLanguage;

            if (closestLang != appLang) {
              await _setLanguageOrVoice(appLang, currentVoices);
            }
            await _tts?.speak(blockChild.physicalPageIndexSemanticsLabel);
            await completer.future;

            if (closestLang != appLang) {
              await _setLanguageOrVoice(closestLang, currentVoices);
            }

            completer = Completer<void>();
          }
          offset += pageBreakText.length;
        }
      }
    } else {
      if (text.isNotEmpty) {
        await _tts?.speak(text);
        await completer.future;
      }
    }

    speakingPageBreak = false;
    pageBreakSelector = null;
    pageBreakText = null;
    R2Log.d('Finished speaking $truncatedText');
  }

  // This function stops the TTS process.
  // It logs a message, sets the playing and abort flags to false and true, respectively, stops the TTS, and waits for the speaking completer to complete.
  Future<void> _stopSpeakingPublication() async {
    R2Log.d('Stop speaking');
    _playing = false;

    _abortCurrent = true;
    await _tts?.stop();
    await _speakingCompleter?.future;
  }
}
