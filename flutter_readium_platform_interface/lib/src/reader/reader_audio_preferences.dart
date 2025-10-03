class AudioPreferences {
  AudioPreferences({
    this.volume,
    this.speed,
    this.pitch,
    this.seekInterval,
    this.controlPanelInfoType,
  });

  double? volume;
  double? speed;
  double? pitch;
  double? seekInterval;
  ControlPanelInfoType? controlPanelInfoType;

  Map<String, dynamic> toMap() => {
        'volume': volume,
        'speed': speed,
        'pitch': pitch,
        'seekInterval': seekInterval,
        'controlPanelInfoType': controlPanelInfoType?.toString().split('.').last,
      };
}

enum ControlPanelInfoType { standard, standardWCh, chapterTitleAuthor, chapterTitle, titleChapter }
