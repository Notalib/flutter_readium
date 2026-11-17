**DRM-protected publications that can't be unlocked now fail to open instead of crashing the reader.**
On iOS, opening an EPUB or PDF reader for an LCP- or Adobe-protected publication crashed the app; on Android the reader opened but could not decrypt the content. `openPublication` now throws a `ReadiumException` with `ReadiumErrorCode.forbidden` on both platforms.
