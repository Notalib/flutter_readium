package dk.nota.flutterreadium.models

import org.json.JSONObject

/**
 * Text associated with a guided navigation object or description.
 *
 * Can be either a plain string or a structured object with optional SSML
 * markup and BCP 47 language tag.
 *
 * See https://readium.org/guided-navigation/schema/text.schema.json
 */
sealed class GuidedNavigationText {
    /** A guided navigation text represented as a plain string. */
    data class StringText(
        val value: String,
    ) : GuidedNavigationText()

    /**
     * A guided navigation text represented as a structured object with optional
     * SSML markup and BCP 47 language tag. At least one of [plain] or [ssml] is non-null.
     */
    data class ObjectText(
        val plain: String?,
        val ssml: String?,
        val language: String?,
    ) : GuidedNavigationText()

    /** Serializes to either a String or a JSONObject depending on the variant. */
    fun toJSON(): Any =
        when (this) {
            is StringText -> {
                value
            }

            is ObjectText -> {
                JSONObject().apply {
                    plain?.let { put("plain", it) }
                    ssml?.let { put("ssml", it) }
                    language?.let { put("language", it) }
                }
            }
        }

    companion object {
        /** Parses a [GuidedNavigationText] from a raw JSON value (String or JSONObject). */
        fun fromJSON(json: Any?): GuidedNavigationText? =
            when (json) {
                is String -> {
                    if (json.isEmpty()) null else StringText(json)
                }

                is JSONObject -> {
                    val plain = json.optString("plain").takeIf { it.isNotEmpty() }
                    val ssml = json.optString("ssml").takeIf { it.isNotEmpty() }
                    val language = json.optString("language").takeIf { it.isNotEmpty() }
                    if (plain == null && ssml == null) {
                        null
                    } else {
                        ObjectText(plain = plain, ssml = ssml, language = language)
                    }
                }

                else -> {
                    null
                }
            }
    }
}
