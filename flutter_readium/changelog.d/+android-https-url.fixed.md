**Android: opening a publication from an `https://` URL failed with an invalid-URL error.**
The absolute-scheme check used `Regex.matches`, which requires the whole string to match the `scheme://` prefix pattern, so every real URL failed it and got a bogus `file://` prepended. The check is now a prefix match.
