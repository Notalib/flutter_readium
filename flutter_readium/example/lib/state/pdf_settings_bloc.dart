import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

abstract class PDFSettingsEvent {}

@immutable
class ChangePDFLayout extends PDFSettingsEvent {
  ChangePDFLayout(this.value);
  final PDFLayout value;
}

@immutable
class ChangePDFReadingProgression extends PDFSettingsEvent {
  ChangePDFReadingProgression(this.value);
  final PDFReadingProgression value;
}

@immutable
class ChangePDFPageSpacing extends PDFSettingsEvent {
  ChangePDFPageSpacing(this.value);
  final double value;
}

@immutable
class ChangePDFFit extends PDFSettingsEvent {
  ChangePDFFit(this.value);
  final PDFFit value;
}

@immutable
class PDFSettingsState {
  const PDFSettingsState({
    this.layout = PDFLayout.paginated,
    this.readingProgression = PDFReadingProgression.ltr,
    this.pageSpacing = 8.0,
    this.fit = PDFFit.auto,
  });

  final PDFLayout layout;
  final PDFReadingProgression readingProgression;
  final double pageSpacing;
  final PDFFit fit;

  PDFSettingsState copyWith({
    PDFLayout? layout,
    PDFReadingProgression? readingProgression,
    double? pageSpacing,
    PDFFit? fit,
  }) {
    return PDFSettingsState(
      layout: layout ?? this.layout,
      readingProgression: readingProgression ?? this.readingProgression,
      pageSpacing: pageSpacing ?? this.pageSpacing,
      fit: fit ?? this.fit,
    );
  }
}

class PDFSettingsBloc extends Bloc<PDFSettingsEvent, PDFSettingsState> {
  final FlutterReadium instance = FlutterReadium();

  void submitPreferenceUpdate() {
    final pdfPreferences = PDFPreferences(
      layout: state.layout,
      readingProgression: state.readingProgression,
      pageSpacing: state.pageSpacing,
      fit: state.fit,
    );
    instance.setPDFPreferences(pdfPreferences);
  }

  PDFSettingsBloc() : super(const PDFSettingsState()) {
    on<ChangePDFLayout>((event, emit) {
      emit(state.copyWith(layout: event.value));
      submitPreferenceUpdate();
    });

    on<ChangePDFReadingProgression>((event, emit) {
      emit(state.copyWith(readingProgression: event.value));
      submitPreferenceUpdate();
    });

    on<ChangePDFPageSpacing>((event, emit) {
      emit(state.copyWith(pageSpacing: event.value));
      submitPreferenceUpdate();
    });

    on<ChangePDFFit>((event, emit) {
      emit(state.copyWith(fit: event.value));
      submitPreferenceUpdate();
    });
  }
}
