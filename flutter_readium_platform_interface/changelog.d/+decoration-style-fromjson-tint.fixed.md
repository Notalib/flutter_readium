**`ReaderDecorationStyle.fromJson` no longer throws for a tinted style.**
It read `tint` as an integer, but `toJson` sends a CSS colour string, so round-tripping any tinted style failed. It now parses the CSS string.
