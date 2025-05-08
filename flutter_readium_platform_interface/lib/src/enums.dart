/// Indicates the current reader widget status.
enum ReadiumReaderStatus {
  open,
  close,
  loading,
  reachedEndOfPublication,
}

extension ReadiumReaderStatusExtension on ReadiumReaderStatus {
  bool get isLoading => name == ReadiumReaderStatus.loading.name;
  bool get isOpen => name == ReadiumReaderStatus.open.name;
  bool get isClose => name == ReadiumReaderStatus.close.name;
  bool get isEndOfPublication => name == ReadiumReaderStatus.reachedEndOfPublication.name;
}

enum TTSVoiceGender { male, female, unspecified }

enum TTSVoiceQuality { low, medium, high }
