**`Locator.locations.progressionEnd` reports where the visible part of the resource ends.**
`progression` only marks the top of the viewport, so it cannot tell whether the end of a chapter is on screen. The new value (0–1, the bottom edge in scroll mode, the last visible column when paginated) reaches 1 once the resource end is visible. Emitted on iOS, Android and web.
