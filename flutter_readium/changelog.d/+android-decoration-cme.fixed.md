**Android: applying decorations while a page loads could crash the app.**
Calling `applyDecorations` for a new group, or clearing a group, while a page was loading could crash with a `ConcurrentModificationException`, because the page-load re-apply was still iterating the decoration groups.
That re-apply now skips groups cleared while it was running, so it no longer brings back decorations that were just removed.
