**Web: synchronised narration keeps moving the text after switching books.**
Opening a media-overlay book after another book could throw "Trying to use frame window when it doesn't exist", and the text stopped following the audio.
A reader view that finished loading after a newer view replaced it could become the active reader, or close the newer book if it failed; it is now discarded.
Frames that are already gone are skipped.
