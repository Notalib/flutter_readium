/// Indicates the current reader widget status.
enum ReadiumReaderStatus {
  loading,
  open,
  close,
  endOfPublication,
}

extension ReadiumReaderStatusExtension on ReadiumReaderStatus {
  bool get isLoading => name == ReadiumReaderStatus.loading.name;
  bool get isOpen => name == ReadiumReaderStatus.open.name;
  bool get isClose => name == ReadiumReaderStatus.close.name;
  bool get isEndOfPublication => name == ReadiumReaderStatus.endOfPublication.name;
}
