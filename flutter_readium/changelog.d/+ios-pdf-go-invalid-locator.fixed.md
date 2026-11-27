**iOS: an unparsable locator passed to `go` on a PDF reader no longer crashes the app.**
The PDF reader force-unwrapped the parsed locator. It now logs a warning and returns without navigating, as the EPUB reader already did.
