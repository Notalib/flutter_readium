**Web: embedding the reader in a larger page disabled the page's scrolling.**
The plugin's bundled stylesheet set `overflow: hidden` on `html` and `body` and restyled the host page's `body`, tables and fonts. It now only styles the reader's own elements. Full-page Flutter apps are unaffected, as Flutter sets these itself.
