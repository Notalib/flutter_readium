import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';

import 'highlight.dart';

final _log = Logger('PublicationBloc');

final Map<String, Locator> savedLocators = {};

@immutable
abstract class PublicationEvent {}

@immutable
class ClosePublication extends PublicationEvent {}

@immutable
class AddHighlight extends PublicationEvent {
  AddHighlight(this.highlight);
  final Highlight highlight;
}

@immutable
class UpdateHighlightColor extends PublicationEvent {
  UpdateHighlightColor(this.id, this.tint);
  final String id;
  final Color tint;
}

@immutable
class DeleteHighlight extends PublicationEvent {
  DeleteHighlight(this.id);
  final String id;
}

@immutable
class OpenPublication extends PublicationEvent {
  OpenPublication({
    required this.publicationUrl,
    this.initialLocator,
    this.autoPlay,
  });
  final String publicationUrl;
  final Locator? initialLocator;
  final bool? autoPlay;
}

class PublicationState {
  PublicationState({
    this.publication,
    this.publicationUrl,
    this.initialLocator,
    this.error,
    this.isLoading = false,
    Map<String, Highlight>? highlights,
  }) : highlights = highlights ?? {};
  final Publication? publication;

  /// Where the current publication was opened from.
  final String? publicationUrl;
  final Locator? initialLocator;
  final dynamic error;
  final bool isLoading;

  /// User highlights for the current publication, keyed by decoration ID.
  /// Not persisted to storage — resets when the publication closes.
  final Map<String, Highlight> highlights;

  /// [highlights] sorted by reading-order resource, then total progression, then progression. A missing value
  /// sorts last, and ties keep creation order. The resource comes first because some locators have no total
  /// progression, such as web WebPub locators and selections on the second page of a spread.
  List<Highlight> get highlightsInReadingOrder {
    final readingOrder = publication?.readingOrder ?? const <Link>[];
    int compare(num? a, num? b) => (a ?? double.infinity).compareTo(b ?? double.infinity);
    int? resourceIndex(Locator locator) => readingOrder.indexOfFirstWithHref(locator.hrefPath);

    final indexed = highlights.values.indexed.toList()
      ..sort((a, b) {
        final la = a.$2.decoration.locator;
        final lb = b.$2.decoration.locator;
        var cmp = compare(resourceIndex(la), resourceIndex(lb));
        if (cmp == 0) cmp = compare(la.locations?.totalProgression, lb.locations?.totalProgression);
        if (cmp == 0) cmp = compare(la.locations?.progression, lb.locations?.progression);
        return cmp != 0 ? cmp : a.$1.compareTo(b.$1);
      });
    return [for (final (_, highlight) in indexed) highlight];
  }

  PublicationState copyWith({
    final Publication? publication,
    final String? publicationUrl,
    final Locator? initialLocator,
    final dynamic error,
    final bool? isLoading,
    final Map<String, Highlight>? highlights,
  }) => PublicationState(
    publication: publication ?? this.publication,
    publicationUrl: publicationUrl ?? this.publicationUrl,
    initialLocator: initialLocator ?? this.initialLocator,
    error: error ?? this.error,
    isLoading: isLoading ?? this.isLoading,
    highlights: highlights ?? this.highlights,
  );

  PublicationState openPublicationSuccess(
    final Publication publication,
    Locator? initialLocator,
    final String publicationUrl,
  ) => PublicationState(
    publication: publication,
    publicationUrl: publicationUrl,
    initialLocator: initialLocator,
    isLoading: false,
    error: null,
  );

  PublicationState openPublicationFail(final dynamic error) =>
      copyWith(publication: publication, error: error, isLoading: false);

  /// Returns true if any field other than [highlights] differs from [other].
  bool hasNonHighlightChanges(PublicationState other) =>
      isLoading != other.isLoading ||
      error != other.error ||
      publication != other.publication ||
      initialLocator != other.initialLocator;

  PublicationState loading(Locator? initialLocator) => copyWith(isLoading: true, initialLocator: initialLocator);

  String errorDebugDescription() {
    if (error is ReadiumException) {
      final re = error as ReadiumException;
      return '${re.code ?? re.codeEnum.name}: ${re.message}';
    } else {
      return error.toString();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'publication': publication?.toJson(),
      'publicationUrl': publicationUrl,
      'initialLocator': initialLocator?.toJson(),
      'error': error?.toString(),
      'isLoading': isLoading,
    };
  }

  static PublicationState? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);

    final publication = Publication.fromJson(
      jsonObject.optNullableMap('publication', remove: true),
    );
    final publicationUrl = jsonObject.optNullableString('publicationUrl', remove: true);
    final initialLocator = Locator.fromJson(
      jsonObject.optNullableMap('initialLocator', remove: true),
    );
    final error = jsonObject.opt('error', remove: true);
    final isLoading = jsonObject.optBoolean(
      'isLoading',
      fallback: false,
      remove: true,
    );

    return PublicationState(
      publication: publication,
      publicationUrl: publicationUrl,
      initialLocator: initialLocator,
      error: error,
      isLoading: isLoading,
    );
  }
}

class PublicationBloc extends HydratedBloc<PublicationEvent, PublicationState> {
  StreamSubscription? timebasedStateSub;
  StreamSubscription? textLocatorSub;
  StreamSubscription? errorEventSub;

  /// Latest reader locator for the open publication, cleared on close.
  Locator? currentLocator;

  final instance = FlutterReadium();

  PublicationBloc() : super(PublicationState()) {
    on<OpenPublication>((final event, final emit) async {
      emit(state.loading(event.initialLocator));
      try {
        final publication = await instance.openPublication(
          event.publicationUrl,
        );
        final pubUrlHashCode = event.publicationUrl.hashCode.toString();
        bool timebasedLocatorReceived = false;

        emit(state.openPublicationSuccess(publication, event.initialLocator, event.publicationUrl));

        // Listen to timebased player state changes to log current locator for debugging purposes.
        timebasedStateSub = instance.onTimebasedPlayerStateChanged
            .map((state) => state.currentLocator)
            .whereNotNull()
            .throttleTime(
              const Duration(milliseconds: 1000),
              leading: false,
              trailing: true,
            )
            .listen((locator) {
              _log.fine('onTimebasedPlayerState.currentLocator: $locator');
              savedLocators[pubUrlHashCode] = locator;
              timebasedLocatorReceived = true;
            });
        textLocatorSub = instance.onTextLocatorChanged.listen((locator) {
          currentLocator = locator;
          _log.fine('onTextLocatorChanged: $locator');
          if ((publication.containsMediaOverlays || publication.containsGuidedNavigation) && timebasedLocatorReceived) {
            // TODO: would be better to check if audio is currently enabled for the publication.
            // If the publication has media overlays, we prefer the locator from the timebased player state.
            return;
          }
          savedLocators[pubUrlHashCode] = locator;
        });
        errorEventSub = instance.onErrorEvent.listen((error) {
          _log.warning('onFlutterReadiumErrorEvent: $error');
        });
      } on Exception catch (error) {
        if (error is ReadiumException) {
          _log.severe(
            'ReadiumException on opening publication: ${error.code ?? error.codeEnum.name} - ${error.message}',
          );
        } else {
          _log.severe(
            'Unknown exception on opening publication: ${error.toString()}',
          );
        }
        emit(state.openPublicationFail(error));
      }
    });

    on<AddHighlight>((final event, final emit) {
      _emitHighlights(emit, {...state.highlights, event.highlight.id: event.highlight});
    });

    on<UpdateHighlightColor>((final event, final emit) {
      final highlight = state.highlights[event.id];
      if (highlight == null) return;
      _emitHighlights(emit, {...state.highlights, event.id: highlight.withTint(event.tint)});
    });

    on<DeleteHighlight>((final event, final emit) {
      _emitHighlights(emit, Map.of(state.highlights)..remove(event.id));
    });

    on<ClosePublication>((final event, final emit) async {
      try {
        instance.closePublication();
        timebasedStateSub?.cancel();
        textLocatorSub?.cancel();
        errorEventSub?.cancel();
      } on Exception catch (error) {
        _log.warning(
          'Exception while closing publication: ${error.toString()}',
        );
      }
      currentLocator = null;
      emit(PublicationState());
    });
  }

  /// Stores [highlights] and re-applies the whole group, since
  /// `applyDecorations` replaces every decoration in it.
  void _emitHighlights(final Emitter<PublicationState> emit, final Map<String, Highlight> highlights) {
    emit(state.copyWith(highlights: highlights));
    instance.applyDecorations(highlightsGroup, [for (final highlight in highlights.values) highlight.decoration]);
  }

  @override
  PublicationState? fromJson(Map<String, dynamic> json) {
    return PublicationState.fromJson(json);
  }

  @override
  Map<String, dynamic>? toJson(PublicationState state) {
    return state.toJson();
  }
}
