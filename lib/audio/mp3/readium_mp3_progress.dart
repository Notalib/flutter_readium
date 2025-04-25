class ReadiumMp3Progress {
  const ReadiumMp3Progress(
    this.index,
    this.position,
  );

  final int index;
  final Duration position;

  @override
  String toString() => '_PlayerPosition(index: $index, position: $position)';

  @override
  bool operator ==(covariant final ReadiumMp3Progress other) {
    if (identical(this, other)) return true;

    return other.index == index && other.position == position;
  }

  @override
  int get hashCode => index.hashCode ^ position.hashCode;
}
