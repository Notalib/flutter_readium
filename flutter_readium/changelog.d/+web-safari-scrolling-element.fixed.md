**Web: EPUB chapters open in Safari again when the publication declares XHTML chapters as `text/html`.**
Such chapters without a DOCTYPE render in quirks mode, where Safari returned a null `document.scrollingElement`, so pagination failed with `TypeError`s and the book did not render.
