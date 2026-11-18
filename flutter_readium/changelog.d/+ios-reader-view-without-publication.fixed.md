**iOS: creating the reader widget while no publication was open crashed the app (`EXC_BREAKPOINT` in the platform view factory).**
The factory now logs, emits the `error` reader status and shows an empty view. A malformed initial locator for a PDF now opens at the start instead of crashing.
