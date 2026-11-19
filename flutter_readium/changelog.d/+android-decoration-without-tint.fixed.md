**Android: decorations without a `tint` were dropped.**
`applyDecorations` threw while parsing a decoration style with no `tint`, so the decoration never rendered, although `tint` is optional in the Dart model.
The tint is now read as optional.
