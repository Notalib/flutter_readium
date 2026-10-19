**Android and web preserve the narration position after a seek to an unknown anchor in the current content file.**

Unknown anchors now leave playback at its previous position. On Android, these seeks could also prevent `play(null)` from resuming; the last valid playback position is now retained.
