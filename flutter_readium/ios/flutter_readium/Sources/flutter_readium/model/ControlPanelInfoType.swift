public enum ControlPanelInfoType {
  case standard
  case standardWCh
  case chapterTitleAuthor
  case chapterTitle
  case titleChapter

  init(from string: String?) {
    switch string {
    case "standard": self = .standard
    case "standardWCh": self = .standardWCh
    case "chapterTitleAuthor": self = .chapterTitleAuthor
    case "chapterTitle": self = .chapterTitle
    case "titleChapter": self = .titleChapter
    default: self = .standard
    }
  }
}
