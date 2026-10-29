**Web now shows custom selection actions in a floating toolbar.**
`ReadiumReaderWidget.selectionActions` was ignored on web. A toolbar now appears next to the selected text, and tapping a button fires `onSelectionAction`.
`allowedDefaultActions` stays unsupported on web, because the browser's own selection menu cannot be customised.
