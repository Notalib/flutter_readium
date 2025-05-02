// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:flutter_readium/flutter_readium.dart';

// abstract class TtsSettingsEvent {}

// class GetTtsVoicesEvent extends TtsSettingsEvent {
//   GetTtsVoicesEvent({this.fallbackLang});
//   final List<String>? fallbackLang;
// }

// class SetTtsVoiceEvent extends TtsSettingsEvent {
//   SetTtsVoiceEvent(this.selectedVoice);
//   final ReadiumTtsVoice selectedVoice;
// }

// class SetTtsHighlightModeEvent extends TtsSettingsEvent {
//   SetTtsHighlightModeEvent(this.highlightMode);
//   final ReadiumHighlightMode highlightMode;
// }

// class ToggleTtsHighlightModeEvent extends TtsSettingsEvent {}

// class SetTtsSpeakPhysicalPageIndexEvent extends TtsSettingsEvent {
//   SetTtsSpeakPhysicalPageIndexEvent(this.speak);
//   final bool speak;
// }

// class TtsSettingsState {
//   TtsSettingsState({
//     this.voices,
//     this.loaded,
//     this.preferredVoices,
//     this.highlightMode,
//     this.ttsSpeakPhysicalPageIndex,
//   });
//   final List<ReadiumTtsVoice>? voices;
//   final bool? loaded;
//   final List<ReadiumTtsVoice>? preferredVoices;
//   final ReadiumHighlightMode? highlightMode;
//   final bool? ttsSpeakPhysicalPageIndex;

//   TtsSettingsState copyWith({
//     final List<ReadiumTtsVoice>? voices,
//     final bool? loaded,
//     final List<ReadiumTtsVoice>? preferredVoices,
//     final ReadiumHighlightMode? highlightMode,
//     final bool? ttsSpeakPhysicalPageIndex,
//   }) =>
//       TtsSettingsState(
//         voices: voices ?? this.voices,
//         loaded: loaded ?? this.loaded,
//         preferredVoices: preferredVoices ?? this.preferredVoices,
//         highlightMode: highlightMode ?? this.highlightMode,
//         ttsSpeakPhysicalPageIndex: ttsSpeakPhysicalPageIndex ?? this.ttsSpeakPhysicalPageIndex,
//       );

//   TtsSettingsState updateVoices(final List<ReadiumTtsVoice> voices) => copyWith(
//         voices: voices,
//         loaded: true,
//       );

//   TtsSettingsState updatePreferredVoices(final ReadiumTtsVoice selectedVoice) {
//     final preferredVoicesList = preferredVoices ?? [];
//     final updatedVoices = preferredVoicesList
//         .where((final voice) => voice.langCode != selectedVoice.langCode)
//         .toList()
//       ..add(selectedVoice);

//     FlutterReadium().updateCurrentTtsVoicesReadium(updatedVoices);

//     return copyWith(preferredVoices: updatedVoices);
//   }

//   TtsSettingsState setHighlightMode(final ReadiumHighlightMode highlightMode) {
//     FlutterReadium().setHighlightMode(highlightMode);
//     return copyWith(highlightMode: highlightMode);
//   }

//   TtsSettingsState setTtsSpeakPhysicalPageIndex(final bool speak) {
//     FlutterReadium().setTtsSpeakPhysicalPageIndex(speak: speak);
//     return copyWith(ttsSpeakPhysicalPageIndex: speak);
//   }
// }

// class TtsSettingsBloc extends Bloc<TtsSettingsEvent, TtsSettingsState> {
//   TtsSettingsBloc()
//       : super(
//           TtsSettingsState(
//             voices: [],
//             loaded: false,
//             preferredVoices: [],
//             highlightMode: ReadiumHighlightMode.paragraph, // to reflect default in ReadiumState
//             ttsSpeakPhysicalPageIndex: false,
//           ),
//         ) {
//     on<GetTtsVoicesEvent>((final event, final emit) async {
//       final voices = await instance.getTtsVoices(fallbackLang: event.fallbackLang);
//       emit(state.updateVoices(voices));
//     });

//     on<SetTtsVoiceEvent>((final event, final emit) async {
//       await instance.setTtsVoice(event.selectedVoice);
//       emit(state.updatePreferredVoices(event.selectedVoice));
//     });

//     on<SetTtsHighlightModeEvent>((final event, final emit) async {
//       emit(state.setHighlightMode(event.highlightMode));
//     });

//     on<ToggleTtsHighlightModeEvent>((final event, final emit) async {
//       final newHighlightMode = state.highlightMode == ReadiumHighlightMode.word
//           ? ReadiumHighlightMode.paragraph
//           : ReadiumHighlightMode.word;
//       emit(state.setHighlightMode(newHighlightMode));
//     });

//     on<SetTtsSpeakPhysicalPageIndexEvent>((final event, final emit) async {
//       emit(state.setTtsSpeakPhysicalPageIndex(event.speak));
//     });
//   }

//   final FlutterReadium instance = FlutterReadium();
// }
