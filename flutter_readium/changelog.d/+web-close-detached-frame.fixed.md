**Web: closing a book with TTS active could break every later open.**
TTS cleanup touched an EPUB frame that was already detached, and the error aborted the close before the navigator was cleared. Detached frames are now skipped.
