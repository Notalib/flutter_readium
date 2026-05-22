import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';

final _log = Logger('PublicationBloc');

final Map<String, Locator> savedLocators = {};

@immutable
abstract class PublicationEvent {}

@immutable
class ClosePublication extends PublicationEvent {}

@immutable
class AddHighlight extends PublicationEvent {
  AddHighlight(this.decoration);
  final ReaderDecoration decoration;
}

@immutable
class OpenPublication extends PublicationEvent {
  OpenPublication({required this.publicationUrl, this.initialLocator, this.autoPlay});
  final String publicationUrl;
  final Locator? initialLocator;
  final bool? autoPlay;
}

class PublicationState {
  PublicationState({
    this.publication,
    this.initialLocator,
    this.error,
    this.isLoading = false,
    Map<String, ReaderDecoration>? highlights,
  }) : highlights = highlights ?? {};
  final Publication? publication;
  final Locator? initialLocator;
  final dynamic error;
  final bool isLoading;

  /// Accumulated decorations for the current publication, keyed by decoration ID.
  /// Not persisted to storage — resets on app restart.
  final Map<String, ReaderDecoration> highlights;

  PublicationState copyWith({
    final Publication? publication,
    final Locator? initialLocator,
    final dynamic error,
    final bool? isLoading,
    final Map<String, ReaderDecoration>? highlights,
  }) => PublicationState(
    publication: publication ?? this.publication,
    initialLocator: initialLocator ?? this.initialLocator,
    error: error ?? this.error,
    isLoading: isLoading ?? this.isLoading,
    highlights: highlights ?? this.highlights,
  );

  PublicationState openPublicationSuccess(final Publication publication, Locator? initialLocator) =>
      PublicationState(publication: publication, initialLocator: initialLocator, isLoading: false, error: null);

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
      ReadiumException re = error as ReadiumException;
      return '${re.type}: ${re.message}';
    } else {
      return error.toString();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'publication': publication?.toJson(),
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

    final publication = Publication.fromJson(jsonObject.optNullableMap('publication', remove: true));
    final initialLocator = Locator.fromJson(jsonObject.optNullableMap('initialLocator', remove: true));
    final error = jsonObject.opt('error', remove: true);
    final isLoading = jsonObject.optBoolean('isLoading', fallback: false, remove: true);

    return PublicationState(
      publication: publication,
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

  final instance = FlutterReadium();

  PublicationBloc() : super(PublicationState()) {
    on<OpenPublication>((final event, final emit) async {
      emit(state.loading(event.initialLocator));
      try {
        final publication = await instance.openPublication(event.publicationUrl);
        final pubUrlHashCode = event.publicationUrl.hashCode.toString();
        bool timebasedLocatorReceived = false;

        emit(state.openPublicationSuccess(publication, event.initialLocator));

        // Listen to timebased player state changes to log current locator for debugging purposes.
        timebasedStateSub = instance.onTimebasedPlayerStateChanged
            .map((state) => state.currentLocator)
            .whereNotNull()
            .throttleTime(const Duration(milliseconds: 5000), leading: false, trailing: true)
            .listen((locator) {
              _log.fine('onTimebasedPlayerState.currentLocator: $locator');
              savedLocators[pubUrlHashCode] = locator;
              timebasedLocatorReceived = true;
            });
        textLocatorSub = instance.onTextLocatorChanged.listen((locator) {
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
          _log.severe('ReadiumException on opening publication: ${error.type} - ${error.message}');
        } else {
          _log.severe('Unknown exception on opening publication: ${error.toString()}');
        }
        emit(state.openPublicationFail(error));
      }
    });

    on<AddHighlight>((final event, final emit) {
      final updated = Map<String, ReaderDecoration>.from(state.highlights)..[event.decoration.id] = event.decoration;
      emit(state.copyWith(highlights: updated));
      instance.applyDecorations('user_highlights', updated.values.toList());
    });

    on<ClosePublication>((final event, final emit) async {
      try {
        instance.closePublication();
        timebasedStateSub?.cancel();
        textLocatorSub?.cancel();
        errorEventSub?.cancel();
      } on Exception catch (error) {
        _log.warning('Exception while closing publication: ${error.toString()}');
      }
      emit(PublicationState());
    });
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
