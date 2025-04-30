class Progressions {
  const Progressions({
    this.progression = 0,
    this.totalProgression = 0,
    this.progressionDuration,
    this.totalProgressionDuration,
  });

  final double progression;
  final double totalProgression;
  final Duration? progressionDuration;
  final Duration? totalProgressionDuration;

  @override
  String toString() => 'Progressions('
      'progression:$progression,'
      'totalProgression:$totalProgression,'
      'progressionDuration:$progressionDuration,'
      'totalProgressionDuration:$totalProgressionDuration)';
}
