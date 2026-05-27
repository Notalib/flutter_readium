package dk.nota.flutterreadium

/**
 * Represents a configured selection action from Dart.
 * These map to custom context menu items shown when text is selected.
 */
data class SelectionActionConfig(
    val id: String,
    val title: String,
)
