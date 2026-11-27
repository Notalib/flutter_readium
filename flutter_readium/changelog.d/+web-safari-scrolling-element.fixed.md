**Web: EPUB chapters open and turn pages in Safari when the publication declares XHTML chapters as `text/html`.**
Such chapters without a DOCTYPE rendered in quirks mode, where Safari returned a null `document.scrollingElement`: pagination threw `TypeError`s, and pages and comic panels did not move. Chapters now get an HTML5 DOCTYPE before rendering, and a guard keeps `scrollingElement` non-null.
