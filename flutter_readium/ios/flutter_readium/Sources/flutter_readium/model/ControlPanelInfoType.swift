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

public enum ControlPanelTimebase {
  case chapter
  case fullBook

  init(from string: String?) {
    switch string?.lowercased() {
    case "fullbook", "full_book": self = .fullBook
    default: self = .chapter
    }
  }
}
