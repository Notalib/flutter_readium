**iOS: audiobook playback no longer stops in the background when the next track loads slowly.**
iOS suspended the app a few seconds after a track ended if the next one had not started, which a slow network made likely. The plugin now holds a background task across the gap (about 30 seconds, set by iOS).
A stalled player now resumes the same item once it has buffered instead of rebuilding the player, and a read error that arrives while paused no longer starts playback.
Lock-screen info and controls are now set up when playback starts through `resume()` as well.
The player now also waits and resumes by itself after a buffer underrun, and `resume()` after a playback failure rebuilds the player instead of doing nothing.
