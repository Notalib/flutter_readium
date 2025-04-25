import '../shared/index.dart';
import 'index.dart';

extension LocationExtension on Locations {
  TimeFragment? get timeFragment =>
      fragments?.map((final e) => TimeFragment.fromFragment(e)).nonNulls.firstOrNull;

  Locations copyWithTimeFragment(final TimeFragment? fragment) {
    final newFragments = [
      ...?fragments?.where((final e) => TimeFragment.fromFragment(e) == null),
      if (fragment != null) fragment.fragment,
    ];

    return copyWith(fragments: newFragments.isEmpty ? null : newFragments);
  }

  Locations copyWithPhysicalPageNumber(final String? index) {
    final newFragments = [
      ...?fragments?.where((final e) => !e.startsWith('physicalPage=')),
      if (index != null) 'physicalPage=$index',
    ];

    return copyWith(fragments: newFragments.isEmpty ? null : newFragments);
  }

  Locations copyWithPage(final int? index) {
    final newFragments = [
      ...?fragments?.where((final e) => !e.startsWith('page=')),
      if (index != null) 'page=$index',
    ];

    return copyWith(fragments: newFragments.isEmpty ? null : newFragments);
  }

  /// Duration must be in seconds.
  /// Passing `null` will remove the existing duration from fragment.
  Locations copyWithFragmentDuration(final num? duration) {
    final newFragments = [
      ...?fragments?.where((final e) => !e.startsWith('duration=')),
      if (duration != null) 'duration=$duration',
    ];

    return copyWith(fragments: newFragments.isEmpty ? null : newFragments);
  }

  String? get physicalPage =>
      fragments?.firstWhereOrNull((final f) => f.startsWith('physicalPage='))?.split('=').last;

  int? get page => int.tryParse(
        fragments?.firstWhereOrNull((final f) => f.startsWith('page='))?.split('=').last ?? '',
      );

  int? get totalPages => int.tryParse(
        fragments?.firstWhereOrNull((final f) => f.startsWith('totalPages='))?.split('=').last ??
            '',
      );

  String? get tocFragment =>
      fragments?.firstWhereOrNull((final f) => f.startsWith('toc='))?.split('=').last;

  int? get durationFragment => int.tryParse(
        fragments?.firstWhereOrNull((final f) => f.startsWith('duration='))?.split('=').last ?? '',
      );
}

class TimeFragment {
  const TimeFragment({this.begin = Duration.zero, this.end});

  final Duration begin;
  final Duration? end;

  static TimeFragment? fromFragment(final String fragment) {
    final match = _audioPattern.firstMatch(fragment);
    if (match == null) {
      return null;
    }
    final begin = match[1]!;
    final end = match[2];
    // Would be better syntax with !? https://github.com/dart-lang/language/issues/361
    return TimeFragment(
      begin: begin.toDuration(),
      end: end?.toDuration(),
    );
  }

  String get fragment {
    final end = this.end;

    return end == null
        ? 't=${begin.toSecondsString()}'
        : 't=${begin.toSecondsString()},${end.toSecondsString()}';
  }

  @override
  String toString() => fragment;
}

/// Should match any number such as '-6.180339887e-1'. Also matches weird “numbers” like '-.E-0000'.
const _num = r'-?(?:[0-9]*\.[0-9]*|[0-9]+)(?:[eE][+-]?[0-9]+)?';
final _audioPattern = RegExp('^t=($_num)?(?:,($_num)?)?\$');
