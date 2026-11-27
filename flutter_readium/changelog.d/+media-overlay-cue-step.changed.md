**`next()` and `previous()` now step one narration cue in media-overlay books.**
Sync narration and guided navigation books now step one cue (a sentence or comic panel) on all platforms. Before, iOS and Android skipped by the seek interval and web jumped to the next audio file.
`previous()` restarts the current cue when more than 2 seconds into it, and a step re-enables narration sync. Use `audioSeekBy` for interval skips.
