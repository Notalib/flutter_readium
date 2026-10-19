**Android PDFs retain their layout and reading position after returning from the background.**

Previously, recreating the reader could revert to its initial layout and position. It now uses the current preferences and reading position.
