import 'package:flutter/foundation.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

abstract class PublicationEvent {}

class ClosePublication extends PublicationEvent {}

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
    this.initialLocator,
    this.error,
    this.isLoading = false,
  });
  final Publication? publication;
  final Locator? initialLocator;
  final dynamic error;
  final bool isLoading;

  PublicationState copyWith({
    final Publication? publication,
    final Locator? initialLocator,
    final dynamic error,
    final bool? isLoading,
  }) =>
      PublicationState(
        publication: publication ?? this.publication,
        initialLocator: initialLocator ?? this.initialLocator,
        error: error ?? this.error,
        isLoading: isLoading ?? this.isLoading,
      );

  PublicationState openPublicationSuccess(final Publication publication, Locator? initialLocator) =>
      PublicationState(publication: publication, initialLocator: initialLocator, isLoading: false, error: null);

  PublicationState openPublicationFail(final dynamic error) =>
      copyWith(publication: publication, error: error, isLoading: false);

  PublicationState loading() => copyWith(isLoading: true);

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

  static PublicationState? fromJson(Map<String, dynamic> json) {
    return PublicationState(
      publication:
          json['publication'] != null ? Publication.fromJson(json['publication'] as Map<String, dynamic>) : null,
      initialLocator:
          json['initialLocator'] != null ? Locator.fromJson(json['initialLocator'] as Map<String, dynamic>) : null,
      error: json['error'],
      isLoading: json['isLoading'] ?? false,
    );
  }
}

class PublicationBloc extends HydratedBloc<PublicationEvent, PublicationState> {
  PublicationBloc() : super(PublicationState()) {
    on<OpenPublication>((final event, final emit) async {
      emit(state.loading());
      try {
        final instance = FlutterReadium();
        final publication = await instance.openPublication(event.publicationUrl);

        emit(state.openPublicationSuccess(publication, event.initialLocator));
      } on Exception catch (error) {
        emit(state.openPublicationFail(error));
      }
    });

    on<ClosePublication>((final event, final emit) async {
      try {
        await FlutterReadium().closePublication();
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
