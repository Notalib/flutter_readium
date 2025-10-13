package dk.nota.flutter_readium.models

import kotlinx.serialization.Serializable
import org.json.JSONObject
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType

@Serializable
class FlutterMediaOverlayItem(val audio: String, val text: String) {
    val audioFile = audio.substringBefore("#")
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

    val textLocator :Locator? by lazy {
        Url.invoke(text.substringBefore("#"))?.let { href ->
            Locator(
                href,
                mediaType = MediaType.XHTML,
                locations = Locator.Locations(listOf("#" + text.substringAfter("#")) ),
            )
        }
    }

    companion object {
        fun fromJson(json: JSONObject): FlutterMediaOverlayItem? {
            val audio = json.optString("audio")
            val text = json.optString("text")
            return if (audio != "" && text != "") {
                FlutterMediaOverlayItem(audio, text)
            } else {
                null
            }
        }
    }
}
