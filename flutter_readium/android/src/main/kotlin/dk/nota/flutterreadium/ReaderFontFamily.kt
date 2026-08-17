package dk.nota.flutterreadium

enum class ReaderFontStyle {
    NORMAL,
    ITALIC,
}

data class ReaderFontFace(
    val asset: String,
    val style: ReaderFontStyle,
    val weight: Int,
)

data class ReaderFontFamily(
    val name: String,
    val fallbacks: List<String>,
    val faces: List<ReaderFontFace>,
) {
    companion object {
        fun fromList(
            value: Any?,
            resolveAsset: (String) -> String,
        ): List<ReaderFontFamily> {
            val families = value as? List<*> ?: return emptyList()
            return families.map { rawFamily ->
                val family = rawFamily as? Map<*, *>
                    ?: throw IllegalArgumentException("Font family declaration must be a map")
                val name = family["name"] as? String
                require(!name.isNullOrBlank()) { "Font family name must not be empty" }

                val fallbacks = (family["fallbacks"] as? List<*> ?: emptyList<Any>()).map { fallback ->
                    require(fallback is String && fallback.isNotBlank()) {
                        "Font family fallback must be a non-empty string"
                    }
                    fallback
                }
                val rawFaces = family["faces"] as? List<*>
                require(!rawFaces.isNullOrEmpty()) { "Font family $name must contain at least one face" }
                val faces = rawFaces.map { rawFace ->
                    val face = rawFace as? Map<*, *>
                        ?: throw IllegalArgumentException("Font face declaration must be a map")
                    val asset = face["asset"] as? String
                    require(!asset.isNullOrBlank()) { "Font face asset must not be empty" }
                    val style = when (face["style"] as? String ?: "normal") {
                        "normal" -> ReaderFontStyle.NORMAL
                        "italic" -> ReaderFontStyle.ITALIC
                        else -> throw IllegalArgumentException("Font face style must be normal or italic")
                    }
                    val weight = (face["weight"] as? Number)?.toInt() ?: 400
                    require(weight in 1..1000) { "Font face weight must be between 1 and 1000" }
                    ReaderFontFace(resolveAsset(asset), style, weight)
                }
                ReaderFontFamily(name, fallbacks, faces)
            }
        }
    }
}
