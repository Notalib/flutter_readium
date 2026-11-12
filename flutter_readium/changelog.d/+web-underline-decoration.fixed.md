**Web: `underline` decorations render as an underline again instead of a filled box.**
Since the Custom Highlight API switch, the plugin's underline CSS no longer matched the toolkit's highlight names, so the decoration fell back to a plain highlight. It now uses the toolkit's own underline style.
