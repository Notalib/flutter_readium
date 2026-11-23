**Margin markers sit next to the text by default.**
A margin marker now keeps a small gap from the text column (`MarginAnchor.text`) instead of sitting at the page edge, which on wide screens can be far from the text. Pass `anchor: MarginAnchor.page` to keep a marker at the page edge, as suits page numbers.
It follows font size, page margins and scroll mode on iOS, Android and web. See the [margin markers guide](https://github.com/Notalib/flutter_readium/blob/main/docs/guides/margin-markers.md#anchoring).
