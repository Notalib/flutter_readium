enum ReadiumHighlightMode {
  paragraph,
  sentence,
  word;

  static ReadiumHighlightMode? optFromString(String? modeStr) {
    switch (modeStr) {
      case 'paragraph':
        return ReadiumHighlightMode.paragraph;
      case 'sentence':
        return ReadiumHighlightMode.sentence;
      case 'word':
        return ReadiumHighlightMode.word;
      default:
        return null;
    }
  }
}
