**Android now honors `goToLocator` calls made while the reader is opening.**

Previously, navigation could be ignored while the reader initialized, leaving it at the initial location. Navigation now waits for the current reader to initialize.
