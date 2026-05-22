package dk.nota.flutter_readium.models

import org.json.JSONArray
import org.json.JSONObject

/**
 * A single step in a guided navigation sequence.
 *
 * Must contain at least one of: [audioref], [imgref], [textref], [videoref],
 * [text], or [children].
 *
 * See https://readium.org/guided-navigation/schema/object.schema.json
 */
data class GuidedNavigationObject(
    val id: String?,
    val audioref: String?,
    val imgref: String?,
    val textref: String?,
    val videoref: String?,
    val text: GuidedNavigationText?,
    val role: List<GuidedNavigationRole>,
    val children: List<GuidedNavigationObject>,
    val description: GuidedNavigationDescription?,
) {
    fun toJSON(): JSONObject =
        JSONObject().apply {
            id?.let { put("id", it) }
            audioref?.let { put("audioref", it) }
            imgref?.let { put("imgref", it) }
            textref?.let { put("textref", it) }
            videoref?.let { put("videoref", it) }
            text?.let { put("text", it.toJSON()) }
            if (role.isNotEmpty()) {
                put("role", JSONArray(role.map { it.value }))
            }
            if (children.isNotEmpty()) {
                put("children", JSONArray(children.map { it.toJSON() }))
            }
            description?.let { put("description", it.toJSON()) }
        }

    companion object {
        fun fromJSON(json: JSONObject?): GuidedNavigationObject? {
            if (json == null) return null

            val id = json.optString("id").takeIf { it.isNotEmpty() }
            val audioref = json.optString("audioref").takeIf { it.isNotEmpty() }
            val imgref = json.optString("imgref").takeIf { it.isNotEmpty() }
            val textref = json.optString("textref").takeIf { it.isNotEmpty() }
            val videoref = json.optString("videoref").takeIf { it.isNotEmpty() }
            val text = GuidedNavigationText.fromJSON(json.opt("text"))

            val roleArray = json.optJSONArray("role")
            val role =
                buildList {
                    if (roleArray != null) {
                        for (i in 0 until roleArray.length()) {
                            GuidedNavigationRole
                                .optFromString(roleArray.optString(i))
                                ?.let { add(it) }
                        }
                    }
                }

            val childrenArray = json.optJSONArray("children")
            val children =
                buildList {
                    if (childrenArray != null) {
                        for (i in 0 until childrenArray.length()) {
                            fromJSON(childrenArray.optJSONObject(i))?.let { add(it) }
                        }
                    }
                }

            val description = GuidedNavigationDescription.fromJSON(json.optJSONObject("description"))

            if (audioref == null && imgref == null && textref == null &&
                videoref == null && text == null && children.isEmpty()
            ) {
                return null
            }

            return GuidedNavigationObject(
                id = id,
                audioref = audioref,
                imgref = imgref,
                textref = textref,
                videoref = videoref,
                text = text,
                role = role,
                children = children,
                description = description,
            )
        }

        fun fromJSONArray(array: JSONArray?): List<GuidedNavigationObject> =
            buildList {
                if (array != null) {
                    for (i in 0 until array.length()) {
                        fromJSON(array.optJSONObject(i))?.let { add(it) }
                    }
                }
            }
    }
}
