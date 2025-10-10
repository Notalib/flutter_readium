package dk.nota.flutter_readium

enum class ControlPanelInfoType {
    STANDARD,
    STANDARD_WCH,
    CHAPTER_TITLE_AUTHOR,
    CHAPTER_TITLE,
    TITLE_CHAPTER;

    companion object {
        fun fromString(value: String): ControlPanelInfoType = when (value) {
            "standard" -> STANDARD
            "standardWCh" -> STANDARD_WCH
            "chapterTitleAuthor" -> CHAPTER_TITLE_AUTHOR
            "chapterTitle" -> CHAPTER_TITLE
            "titleChapter" -> TITLE_CHAPTER
            else -> STANDARD
        }

        fun toString(type: ControlPanelInfoType): String = when (type) {
            STANDARD -> "standard"
            STANDARD_WCH -> "standardWCh"
            CHAPTER_TITLE_AUTHOR -> "chapterTitleAuthor"
            CHAPTER_TITLE -> "chapterTitle"
            TITLE_CHAPTER -> "titleChapter"
        }
    }

}
