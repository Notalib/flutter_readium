class TtsPosition {
  const TtsPosition({this.chapter = 0, this.block = 0, this.blockOffset = 0});

  final int chapter;
  final int block;
  final int blockOffset;

  TtsPosition nextChapter() => TtsPosition(chapter: chapter + 1);

  TtsPosition atBlock(final int newBlock) => TtsPosition(chapter: chapter, block: newBlock);

  TtsPosition nextBlock() => atBlock(block + 1);

  TtsPosition atBlockOffset(final int newBlockOffset) =>
      TtsPosition(chapter: chapter, block: block, blockOffset: newBlockOffset);

  @override
  String toString() => 'Position(chapter: $chapter, block: $block, blockOffset: $blockOffset)';
}
