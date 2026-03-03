import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../state/tts_settings_bloc.dart';
import 'index.dart';

class TtsSettingsWidget extends StatefulWidget {
  const TtsSettingsWidget({required this.pubLang, super.key});

  final List<String> pubLang;

  @override
  State<TtsSettingsWidget> createState() => _TtsSettingsWidgetState();
}

class _TtsSettingsWidgetState extends State<TtsSettingsWidget> {
  String? selectedLanguage;
  ReaderTTSVoice? selectedVoice;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(final BuildContext context) => SafeArea(
    child: Wrap(
      children: [
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Semantics(
            header: true,
            child: const Align(
              alignment: Alignment.center,
              child: Text('TTS settings', style: TextStyle(fontSize: 25)),
            ),
          ),
        ),
        const Divider(),
        SingleChildScrollView(
          child: Column(
            children: [
              ListItemWidget(label: 'Voice', child: _buildVoiceOptions(context)),
              /*
              const Divider(),
              // TODO: Remember that it will only highlight paragraphs if google network voices are used. Implement this in the UI.
              ListItemWidget(
                label: 'Highlight',
                child: BlocBuilder<TtsSettingsBloc, TtsSettingsState>(
                  builder: (final context, final state) {
                    final chosenVoices = _findVoicesByLangCode(state, widget.pubLang);
                    final isGoogleNetworkVoice =
                        Platform.isAndroid && chosenVoices.any((final voice) => voice.networkRequired);
                    final highlightModes = isGoogleNetworkVoice
                        ? [ReadiumHighlightMode.paragraph]
                        : ReadiumHighlightMode.values;

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ToggleButtons(
                        isSelected: highlightModes.map((final mode) => mode == state.highlightMode).toList(),
                        selectedBorderColor: Colors.blue,
                        borderWidth: 4.0,
                        borderColor: Colors.transparent,
                        onPressed: (final index) {
                          context.read<TtsSettingsBloc>().add(
                            SetTtsHighlightModeEvent(ReadiumHighlightMode.values[index]),
                          );
                        },
                        children: highlightModes
                            .map(
                              (final mode) => SizedBox(
                                width: 120,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  child: Center(
                                    child: Text(
                                      mode.toString().split('.').last[0].toUpperCase() +
                                          mode.toString().split('.').last.substring(1).toLowerCase(),
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              ListItemWidget(
                label: 'Announce page numbers',
                isVerticalAlignment: true,
                child: BlocSelector<TtsSettingsBloc, TtsSettingsState, bool>(
                  selector: (final state) => state.ttsSpeakPhysicalPageIndex ?? false,
                  builder: (final context, final ttsSpeakPhysicalPageIndex) => Switch(
                    value: ttsSpeakPhysicalPageIndex,
                    onChanged: (final value) {
                      context.read<TtsSettingsBloc>().add(SetTtsSpeakPhysicalPageIndexEvent(value));
                    },
                  ),
                ),
              ),
            */
              const Divider(),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: ButtonStyle(
                  padding: WidgetStateProperty.all<EdgeInsets>(const EdgeInsets.symmetric(vertical: 16.0)),
                  shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(0.0)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 8.0,
                  children: [
                    Icon(Icons.close, size: 20),
                    // SizedBox(width: 10),
                    Text('Close', style: TextStyle(fontSize: 20)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildVoiceOptions(final BuildContext context) {
    final ttsSettingsBloc = context.watch<TtsSettingsBloc>();
    final state = ttsSettingsBloc.state;

    final voices = state.voices;
    final voiceLanguages = voices?.map((final voice) => voice.language).sortedBy((final lang) => lang).toSet();
    final preferredVoices = state.preferredVoices;

    final voicesLoaded = state.loaded ?? false;

    final preferredLanguage = voiceLanguages != null
        ? preferredVoices
              ?.firstWhereOrNull((final preferredVoice) => voiceLanguages.contains(preferredVoice.language))
              ?.language
        : null;

    final showVoiceOptions =
        voicesLoaded &&
        voices != null &&
        voices.isNotEmpty &&
        (selectedLanguage != null || preferredLanguage != null || voiceLanguages == null || voiceLanguages.length == 1);

    if (!voicesLoaded) return const CircularProgressIndicator();
    if (voicesLoaded && (voices == null || voices.isEmpty)) {
      return const Text('No voices available');
    }
    if (voicesLoaded && voices != null && voices.isNotEmpty) {
      return Row(
        children: [
          if (voiceLanguages != null && voiceLanguages.length > 1)
            DropdownButton<String>(
              value: selectedLanguage ?? preferredLanguage,
              onChanged: (final language) {
                setState(() {
                  selectedLanguage = language;
                  selectedVoice = null;
                });
              },
              items: voiceLanguages
                  .map((final language) => DropdownMenuItem<String>(value: language, child: Text(language)))
                  .toList(),
            ),
          if (showVoiceOptions)
            DropdownButton<ReaderTTSVoice>(
              value:
                  selectedVoice ??
                  preferredVoices?.firstWhereOrNull(
                    (final preferredVoice) => voices
                        .where((final voice) => voice.language == selectedLanguage || selectedLanguage == null)
                        .contains(preferredVoice),
                  ),
              onChanged: (final voice) {
                ttsSettingsBloc.add(SetTtsVoiceEvent(voice!));
                setState(() {
                  selectedVoice = voice;
                });
              },
              items: voices
                  .where((final voice) => voice.language == selectedLanguage || selectedLanguage == null)
                  .map((final voice) => DropdownMenuItem<ReaderTTSVoice>(value: voice, child: Text(voice.name)))
                  .toList(),
            ),
        ],
      );
    }
    return const Text('Something went wrong. Please try again.');
  }
}

List<ReaderTTSVoice> _findVoicesByLangCode(final TtsSettingsState state, final List<String> pubLang) =>
    state.preferredVoices?.where((final voice) => pubLang.contains(voice.language)).toList() ?? [];
