package dk.nota.flutterreadium

enum class PageBreakBehavior {
    READ_AS_IS,
    PREFIX_LABEL,
    SKIP,
    ;

    companion object {
        fun fromString(value: String?): PageBreakBehavior? =
            when (value?.lowercase()) {
                "readasis" -> READ_AS_IS
                "prefixlabel" -> PREFIX_LABEL
                "skip" -> SKIP
                else -> null
            }

        fun toString(b: PageBreakBehavior): String =
            when (b) {
                READ_AS_IS -> "readAsIs"
                PREFIX_LABEL -> "prefixLabel"
                SKIP -> "skip"
            }
    }
}
