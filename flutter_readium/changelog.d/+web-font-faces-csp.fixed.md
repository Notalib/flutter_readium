**Web: custom fonts from `fontFamilyDeclarations` never loaded in EPUBs.**
The EPUB frame's Content Security Policy only allowed fonts from the publication's own location, so the browser blocked the app's font assets. The app's asset directory is now allowed too.
