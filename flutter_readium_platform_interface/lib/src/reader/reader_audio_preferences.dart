class AudioPreferences {
  AudioPreferences({
    this.volume,
    this.speed,
    this.pitch,
    this.seekInterval,
    this.allowExternalSeeking,
    this.controlPanelInfoType,
  });

  double? volume;
  double? speed;
  double? pitch;
  double? seekInterval;
  bool? allowExternalSeeking;
  double? updateIntervalSecs;
  ControlPanelInfoType? controlPanelInfoType;

  Map<String, dynamic> toMap() => {
        'volume': volume,
        'speed': speed,
        'pitch': pitch,
        'seekInterval': seekInterval,
        'allowExternalSeeking': allowExternalSeeking,
        'updateIntervalSecs': updateIntervalSecs,
        'controlPanelInfoType': controlPanelInfoType?.toString().split('.').last,
      };
}

enum ControlPanelInfoType { standard, standardWCh, chapterTitleAuthor, chapterTitle, titleChapter }
