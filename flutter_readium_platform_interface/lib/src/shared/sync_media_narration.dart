import '../_index.dart';

part 'sync_media_narration.freezed.dart';
part 'sync_media_narration.g.dart';

/// Based on https://w3c.github.io/sync-media-pub
///
/// [Json Schema](https://raw.githubusercontent.com/w3c/sync-media-pub/master/drafts/schema/sync-media-narration.schema.json)
@freezedExcludeUnion
abstract class SyncMediaNarration with _$SyncMediaNarration {
  const factory SyncMediaNarration({
    /// Ordered list of children, similar to SMIL 'seq' element
    /// (recursive JSON Schema property),
    final List<SyncMediaNarration>? narration,

    /// Document reference, similar to SMIL 'text' element,
    /// e.g. 'chapter1.html#paragraph1',
    final String? text,

    /// Audio reference, similar to SMIL 'audio' element,
    /// e.g. 'chapter1.mp3?t=0,123',
    final String? audio,

    /// Type associated with this synchronized narration sequence, similar to
    /// EPUB3 'epub:type' attribute semantics, e.g. 'aside',
    @stringListJson final List<String>? role,
  }) = _SyncMediaNarration;

  factory SyncMediaNarration.fromJson(final Map<String, dynamic> json) => _$SyncMediaNarrationFromJson(json);
}

extension ReadiumSyncMediaNarration on SyncMediaNarration {
  Uri? get uri => Uri.tryParse(text ?? '');

  String? get cssSelector => uri?.hasFragment == true ? '#${uri?.fragment}' : null;

  Iterable<SyncMediaNarration> get recursiveNarrations sync* {
    yield this;
    for (final n in narration ?? const <SyncMediaNarration>[]) {
      yield* n.recursiveNarrations;
    }
  }

  /// Returns resource name from [audio].
  String? get resource => audio == null ? null : _audioPattern.firstMatch(audio!)?[1];

  /// Returns begin duration from [audio].
  Duration? get audioBegin => audio == null ? null : _parseDurationDoubleNullable(_audioPattern.firstMatch(audio!)?[2]);

  /// Returns end duration from [audio].
  Duration? get audioEnd => audio == null ? null : _parseDurationDoubleNullable(_audioPattern.firstMatch(audio!)?[3]);

  bool contains(final Duration position) =>
      (audioBegin == null || audioBegin! <= position) && (audioEnd == null || position < audioEnd!);

  SyncMediaNarration? find(final Duration position) =>
      recursiveNarrations.firstWhereOrNull((final n) => n.contains(position));

  /// Negative if before beginning, positive if after end, zero if in range.
  Duration signedDistanceFrom(final Duration position) {
    final begin = audioBegin;
    final end = audioEnd;

    return begin != null && position < begin
        ? position - begin
        : end != null && end <= position
            ? position - end
            : Duration.zero;
  }

  /// Finds the narration containing or just before position, or just after position if none are before.
  SyncMediaNarration? findFuzzy(final Duration position) {
    SyncMediaNarration? best;
    var bestScore = 2000000000000;
    for (final narration in recursiveNarrations) {
      if (narration.audio == null) {
        continue;
      }

      final distance = narration.signedDistanceFrom(position);

      if (distance == Duration.zero) {
        // Return exact match immediately.
        return narration;
      }
      final score = distance.inMicroseconds.abs() + (distance.isNegative ? 1000000000000 : 0);
      if (score < bestScore) {
        best = narration;
        bestScore = score;
      }
    }
    return best;
  }

  Locator? toLocator({
    final String? title,
    final double? progression,
    final double? totalProgression,
    final Duration? chapterDuration,
    final Duration? totalProgressionDuration,
    final Duration? progressionDuration,
    final int? position,
  }) {
    final href = text?.path;

    if (href == null) {
      R2Log.e(
        'Missing or invalid text',
        data: {'narration': this},
      );

      return null;
    }

    return Locator(
      href: href,
      type: MediaType.mp3.value,
      title: title,
      locations: Locations(
        position: position,
        cssSelector: cssSelector,
        fragments: chapterDuration == null && audioBegin == null
            ? null
            : [TimeFragment(begin: progressionDuration ?? audioBegin!).toString()],
        xFragmentDuration: duration,
        progression: progression,
        totalProgression: totalProgression,
        xChapterDuration: chapterDuration,
        xProgressionDuration: progressionDuration ?? audioBegin,
        xTotalProgressionDuration: totalProgressionDuration,
      ),
    );
  }

  Iterable<SyncMediaNarration> get narrationsWithNonNullText => recursiveNarrations.where((final n) => n.text != null);

  Duration? get duration {
    final begin = audioBegin;
    final end = audioEnd;

    if (begin == null || end == null) {
      return null;
    }

    return end - begin;
  }

  Duration? _parseDurationDoubleNullable(final String? s) =>
      s != null ? const Duration(seconds: 1) * double.parse(s) : null;
}

/// Should match any number such as '-6.180339887e-1'. Also matches weird “numbers” like '-.E-0000'.
const _num = r'-?(?:[0-9]*\.[0-9]*|[0-9]+)(?:[eE][+-]?[0-9]+)?';
final _audioPattern = RegExp('^([^#]+)?(?:#t=($_num)?(?:,($_num)?)?)?\$');
