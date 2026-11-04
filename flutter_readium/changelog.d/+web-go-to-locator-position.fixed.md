**Web: `goToLocator` ignored the position inside a chapter.**
Only the chapter's href reached the navigator, so fragments, progression and text were dropped and the chapter opened at its first page. The full locator is now passed on. A position-less `initialLocator` also keeps its progression and text.
