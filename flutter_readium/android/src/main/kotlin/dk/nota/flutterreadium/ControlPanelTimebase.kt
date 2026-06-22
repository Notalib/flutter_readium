package dk.nota.flutterreadium

enum class ControlPanelTimebase {
    CHAPTER,
    FULL_BOOK,
    ;

    companion object {
        fun fromString(value: String): ControlPanelTimebase =
            when (value) {
                "chapter" -> CHAPTER
                "fullBook" -> FULL_BOOK
                else -> CHAPTER
            }

        fun toString(type: ControlPanelTimebase): String =
            when (type) {
                CHAPTER -> "chapter"
                FULL_BOOK -> "fullBook"
            }
    }
}
