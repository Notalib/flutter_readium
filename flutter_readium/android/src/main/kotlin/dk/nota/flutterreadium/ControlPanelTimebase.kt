package dk.nota.flutterreadium

enum class ControlPanelTimebase {
    CHAPTER,
    WHOLE_BOOK,
    ;

    companion object {
        fun fromString(value: String): ControlPanelTimebase =
            when (value.lowercase()) {
                "chapter" -> CHAPTER
                "wholebook" -> WHOLE_BOOK
                "whole_book" -> WHOLE_BOOK
                else -> CHAPTER
            }

        fun toString(type: ControlPanelTimebase): String =
            when (type) {
                CHAPTER -> "chapter"
                WHOLE_BOOK -> "wholeBook"
            }
    }
}
