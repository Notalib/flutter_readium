import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

abstract class PublicationEvent {}

class OpenPublication extends PublicationEvent {
  OpenPublication({
    required this.publication,
    this.initialLocator,
    this.autoPlay,
  });
  final Publication publication;
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
      copyWith(publication: publication, initialLocator: initialLocator, isLoading: false);

  PublicationState openPublicationFail(final dynamic error) =>
      copyWith(publication: publication, error: error, isLoading: false);

  PublicationState loading() => copyWith(isLoading: true);

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
        // TODO: Set which Publication is rendered on the native side.
        // final publication = await FlutterReadium().setRenderedPublication(
        //   event.publication.identifier,
        // initialLocator: event.initialLocator,
        // autoPlay: event.autoPlay ?? false,
        // preload: false,
        // );
        emit(state.openPublicationSuccess(event.publication, event.initialLocator));
      } on Exception catch (error) {
        emit(state.openPublicationFail(error));
      }
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
