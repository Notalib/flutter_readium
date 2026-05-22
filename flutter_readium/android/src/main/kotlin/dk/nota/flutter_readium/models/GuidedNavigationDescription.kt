package dk.nota.flutter_readium.models

import org.json.JSONObject

/**
 * Alternative description for a guided navigation object, using one or more
 * media references.
 *
 * At least one of [audioref], [imgref], [textref], [videoref], or [text] must be present.
 *
 * See https://readium.org/guided-navigation/schema/description.schema.json
 */
data class GuidedNavigationDescription(
    val audioref: String?,
    val imgref: String?,
    val textref: String?,
    val videoref: String?,
    val text: GuidedNavigationText?,
) {
    fun toJSON(): JSONObject =
        JSONObject().apply {
            audioref?.let { put("audioref", it) }
            imgref?.let { put("imgref", it) }
            textref?.let { put("textref", it) }
            videoref?.let { put("videoref", it) }
            text?.let { put("text", it.toJSON()) }
        }

    companion object {
        fun fromJSON(json: JSONObject?): GuidedNavigationDescription? {
            if (json == null) return null

            val audioref = json.optString("audioref").takeIf { it.isNotEmpty() }
            val imgref = json.optString("imgref").takeIf { it.isNotEmpty() }
            val textref = json.optString("textref").takeIf { it.isNotEmpty() }
            val videoref = json.optString("videoref").takeIf { it.isNotEmpty() }
            val text = GuidedNavigationText.fromJSON(json.opt("text"))

            if (audioref == null && imgref == null && textref == null &&
                videoref == null && text == null
            ) {
                return null
            }

            return GuidedNavigationDescription(
                audioref = audioref,
                imgref = imgref,
                textref = textref,
                videoref = videoref,
                text = text,
            )
        }
    }
}
