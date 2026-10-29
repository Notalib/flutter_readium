**Web: EPUBs failed to open in release builds when `fontFamilyDeclarations` was set.**
The minified bundle resolved the font base URL from the wrong variable, so loading a chapter threw `Invalid URL`. Font faces now resolve against the host page again.
