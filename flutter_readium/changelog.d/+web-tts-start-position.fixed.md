**Web: TTS starts at the page the reader is on instead of the start of the book.**
`ttsEnable` started at the first resource, and `play(null)` restarted from there. TTS now starts at the first paragraph visible in the reader when `play` is called, also on a chapter's last page and when `play` gets the reader's own locator, and `play(null)` resumes at the current utterance. Starting from a TTS locator mid-chapter works too; it used to restart at the top of the chapter.
Without a chosen voice, TTS now picks an installed voice for the text's language and never a macOS novelty voice such as "Albert". The browser used to read with its default voice, whatever language it spoke.
The first utterance after a page load no longer stalls for 8 seconds in Chrome.
`play` after `pause` speaks again; Chrome used to queue the utterance silently.
