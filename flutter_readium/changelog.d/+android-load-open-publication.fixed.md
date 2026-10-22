**Android: `loadPublication` on the open book broke the reader.**
Loading the URL of the open publication returned the open instance, which the plugin then closed, so the reader showed a blank book. This also made the example app's book fail to load after a hot restart with the reader open. `loadPublication` now always loads a separate copy.
