package dk.nota.flutter_readium.models

import org.json.JSONObject
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import java.io.Serializable

data class FlutterMediaOverlayItem(
    val audio: String,
    val text: String,
    val position: Int,
    val title: String
) : Serializable {
    val audioFile = audio.substringBefore("#")
    val textFile = text.substringBefore("#")
    val textId = text.substringAfter("#", "")
    private val audioFragment = audio.substringAfter("#", "")
    private val audioTime =
        if (audioFragment.startsWith("t=")) audioFragment.substringAfter("t=") else null

    val audioStart: Double? = audioTime?.substringBefore(",")?.toDoubleOrNull()
    val audioEnd: Double? = audioTime?.substringAfter(",", "")?.toDoubleOrNull()

    fun isInRange(audioIn: String, time: Double): Boolean {
        if (audioIn.substringBefore("#") != audioFile) return false
        val start = audioStart ?: return false
        val end = audioEnd ?: return time >= start
        return time in start..end
    }

    val textLocator: Locator? by lazy {
        Url.invoke(text.substringBefore("#"))?.let { href ->
            Locator(
                href,
                mediaType = MediaType.XHTML,
                title = title,
                locations = Locator.Locations(
                    listOf("#" + text.substringAfter("#")),
                    otherLocations = mapOf<String, Any>("cssSelector" to "#$textId"),
                    position = position,
                ),
            )
        }
    }

    val audioLocator: Locator? by lazy {
        Url.invoke(textFile)?.let { href ->
            Locator(
                href,
                title = title,
                mediaType = MediaType.MP3,
                locations = Locator.Locations(
                    fragments = listOf("t=${audioStart ?: 0.0}"),
                    otherLocations = mapOf<String, Any>("cssSelector" to "#$textId"),
                    position = position,
                ),
            )
        }
    }

    companion object {
        fun fromJson(json: JSONObject, position: Int, title: String): FlutterMediaOverlayItem? {
            val audio = json.optString("audio")
            val text = json.optString("text")
            return if (audio != "" && text != "") {
                FlutterMediaOverlayItem(audio, text, position, title)
            } else {
                null
            }
        }
    }
}
