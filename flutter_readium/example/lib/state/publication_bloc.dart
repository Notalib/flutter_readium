import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rxdart/rxdart.dart';

final Map<String, Locator> savedLocators = {};

@immutable
abstract class PublicationEvent {}

@immutable
class ClosePublication extends PublicationEvent {}

@immutable
class OpenPublication extends PublicationEvent {
  OpenPublication({required this.publicationUrl, this.initialLocator, this.autoPlay});
  final String publicationUrl;
  final Locator? initialLocator;
  final bool? autoPlay;
}

class PublicationState {
  PublicationState({this.publication, this.initialLocator, this.error, this.isLoading = false});
  final Publication? publication;
  final Locator? initialLocator;
  final dynamic error;
  final bool isLoading;

  PublicationState copyWith({
    final Publication? publication,
    final Locator? initialLocator,
    final dynamic error,
    final bool? isLoading,
  }) => PublicationState(
    publication: publication ?? this.publication,
    initialLocator: initialLocator ?? this.initialLocator,
    error: error ?? this.error,
    isLoading: isLoading ?? this.isLoading,
  );

  PublicationState openPublicationSuccess(final Publication publication, Locator? initialLocator) =>
      PublicationState(publication: publication, initialLocator: initialLocator, isLoading: false, error: null);

  PublicationState openPublicationFail(final dynamic error) =>
      copyWith(publication: publication, error: error, isLoading: false);

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

        emit(state.openPublicationSuccess(publication, event.initialLocator));

        // Listen to timebased player state changes to log current locator for debugging purposes.
        timebasedStateSub = instance.onTimebasedPlayerStateChanged
            .map((state) => state.currentLocator)
            .whereNotNull()
            .throttleTime(const Duration(milliseconds: 5000), leading: false, trailing: true)
            .listen((locator) {
              debugPrint('onTimebasedPlayerState.currentLocator: $locator');
              savedLocators[pubUrlHashCode] = locator;
            });
        textLocatorSub = instance.onTextLocatorChanged.listen((locator) {
          debugPrint('onTextLocatorChanged: $locator');
          // TODO: should only be used if NOT audioEnabled.
          if (publication.conformsToReadiumAudiobook || publication.containsMediaOverlays == true) {
            // For audio books, we want to save the locator from the timebased state changes,
            // which is more accurate for tracking the current visual position in the book.
            return;
          }
          savedLocators[pubUrlHashCode] = locator;
        });
        errorEventSub = instance.onErrorEvent.listen((error) {
          debugPrint('onFlutterReadiumErrorEvent: $error');
        });
      } on Exception catch (error) {
        if (error is ReadiumException) {
          debugPrint('ReadiumException on opening publication: ${error.type} - ${error.message}');
        } else {
          debugPrint('Unknown exception on opening publication: ${error.toString()}');
        }
        emit(state.openPublicationFail(error));
      }
    });

    on<ClosePublication>((final event, final emit) async {
      try {
        instance.closePublication();
        timebasedStateSub?.cancel();
        textLocatorSub?.cancel();
        errorEventSub?.cancel();
      } on Exception catch (error) {
        debugPrint('Exception while closing publication: ${error.toString()}');
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
