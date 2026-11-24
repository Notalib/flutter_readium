**Android, iOS: fix incorrect resume positions in narrated books.**
Books with multiple audio tracks for the same text resource could resume at the
wrong position. Restoration now uses saved text anchors to identify the track when
unambiguous and preserves the saved audio time.
