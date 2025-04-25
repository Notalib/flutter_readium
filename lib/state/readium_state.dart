library;

import '../_index.dart';

part 'readium_state.freezed.dart';
part 'readium_state.g.dart';

typedef PhysicalPageIndexSemanticFormatter = String Function(String value);

typedef ReadiumStateType = $ReadiumStateCopyWith;

@Freezed(
  makeCollectionsUnmodifiable: false,
  fromJson: false,
  toJson: true,
)
abstract class ReadiumState with _$ReadiumState {
  const ReadiumState._();

  @JsonSerializable(
    explicitToJson: true,
  )
  const factory ReadiumState({
    /// ======================================
    /// ############ Preload
    /// ======================================

    final double? preloadProgress,
    @Default(ReadiumPreloadStatus.none) final ReadiumPreloadStatus preloadStatus,

    /// ======================================
    /// ############ OPDS
    /// ======================================

    /// True if the publication is currently being opened.
    @Default(false) final bool opening,
    final Publication? publication,
    final OPDSPublication? opdsPublication,
    final Map<String, String>? httpHeaders,

    /// ======================================
    /// ############ Audio
    /// ======================================
    final Locator? audioLocator,

    /// True if TTS should be enabled, false if the TTS audio handler doesn't need to be started.
    @Default(ReadiumAudioStatus.none) final ReadiumAudioStatus audioStatus,
    @Default(false) final bool playing,
    @Default(false) final bool autoPlay,

    /// TODO: Interval cannot be set dynamically in audio_service,
    /// https://github.com/ryanheise/audio_service/issues/683
    @Default(Duration(seconds: 15)) final Duration skipIntervalDuration,
    @Default(1.0) final double playbackRate,

    // Allow audio controller in notification/control center and locked screen to have a interactive progress bar.
    @Default(true) final bool allowExternalSeeking,

    // Swap pub information with chapter information in notification/control center and locked screen if true.
    @Default(false) final bool swapChapterInfo,

    /// ======================================
    /// ############ TTS
    /// ======================================
    @Default(false) final bool ttsEnabled,

    /// Only for TTS.
    /// True if TTS should speak the page index.
    @Default(false) final bool ttsSpeakPhysicalPageIndex,

    // App language to handle speak physical page index, where the text is always in app language.
    final String? appLanguage,

    /// Only for TTS.
    /// Example: (page) => 'Here starts page ${page},
    @JsonKey(includeFromJson: false, includeToJson: false)
    final PhysicalPageIndexSemanticFormatter? physicalPageIndexSemanticsFormatter,

    /// Only for TTS.
    /// TTS Voice user preferences
    final List<ReadiumTtsVoice>? currentTtsVoices,

    /// ======================================
    /// ############ Reader
    /// ======================================

    final Locator? textLocator,

    /// Reader widget status.
    @Default(ReadiumReaderStatus.close) final ReadiumReaderStatus readerStatus,

    /// True if [textLocator] is in synch with [audioLocator], false if [textLocator] is not in synch
    /// or `null` if there is no current text widget to synch with.
    @Default(true) final bool audioMatchesText,

    /// Current highlight mode of current location. Mostly used by TTS.
    @Default(ReadiumHighlightMode.paragraph) final ReadiumHighlightMode highlightMode,

    /// True while user manual swiping in reader view.
    @Default(false) final bool readerSwiping,

    /// Properties passed to reader widget.
    @Default(ReadiumReaderProperties()) final ReadiumReaderProperties readerProperties,

    /// ======================================
    /// ############ Error
    ///=======================================

    final ReadiumError? error,
  }) = _ReadiumState;

  /// Helper to update the state.
  @JsonKey(includeFromJson: false, includeToJson: false)
  ReadiumStateType get update =>
      _$ReadiumStateCopyWithImpl(this, (final state) => FlutterReadium.state = state);
}
