**Web: scroll mode stayed at progression 0 while scrolling a chapter.**
A guard against a null `document.scrollingElement` pointed it at `<body>`, which never scrolls in standards-mode EPUB documents. It now falls back to `<body>` only when the browser returns null.
