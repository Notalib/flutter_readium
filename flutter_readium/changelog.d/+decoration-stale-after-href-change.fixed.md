**Android: a decoration that keeps its id but moves to another chapter (e.g. the TTS highlight) stayed visible in the old chapter.**
The toolkit diffs decorations by id and only updates the new chapter, so the old chapter's highlight was never removed and showed up stale when navigating back. The plugin now clears the group first when an id changes chapter.
