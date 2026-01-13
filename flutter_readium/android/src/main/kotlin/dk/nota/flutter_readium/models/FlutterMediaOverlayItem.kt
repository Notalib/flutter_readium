package dk.nota.flutter_readium.models

import org.json.JSONObject
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import java.io.Serializable

/**
 * A single media overlay item mapping audio to text.
 */
data class FlutterMediaOverlayItem(
    /**
     * The audio reference, e.g. "chapter1.mp3#t=12.34,15.67" or "chapter1.mp3"
     */
    val audio: String,

    /**
     * The text reference, e.g. "chapter1.html#para34" or "chapter1.html"
     */
    val text: String,

    /**
     * The position in the reading order (1-based index)
     */
    val position: Int,

    /**
     * The title of the chapter or section this item belongs to
     */
    val title: String
) : Serializable {
    /**
     * The audio file without the fragment (e.g. "chapter1.mp3")
     */
    val audioFile = audio.substringBefore("#")

    /**
     * The media type of the audio file
     */
    val audioMediaType = when (audioFile.split('.').lastOrNull()) {
        "mp3" -> MediaType.MP3
        "opus" -> MediaType.OPUS
        else -> MediaType.MP3
    }

    /**
     * The text file without the fragment (e.g. "chapter1.html")
     */
    val textFile = text.substringBefore("#")

    /**
     * The text fragment identifier (e.g. "para34"), or empty string if none
     */
    val textId = text.substringAfter("#", "")
    private val audioFragment = audio.substringAfter("#", "")

    /**
     * The audio time fragment minus the t= (e.g. "12.34,15.67"), or null if none
     */
    private val audioTime =
        if (audioFragment.startsWith("t=")) audioFragment.substringAfter("t=") else null

    /**
     * The start time in seconds, or null if none
     */
    val audioStart: Double? = audioTime?.substringBefore(",")?.toDoubleOrNull()

    /**
     * The end time in seconds, or null if none
     */
    val audioEnd: Double? = audioTime?.substringAfter(",")?.toDoubleOrNull()

    /**
     * Is this item in range for the given file reference and time offset?
     */
    fun isInRange(fileRef: Url, time: Double): Boolean {
        if (!fileRef.isEquivalent(Url.invoke(textFile))) {
            if (!fileRef.isEquivalent(Url.invoke(audioFile))) {
                return false
            }
        }

        val start = audioStart ?: return false
        val end = audioEnd ?: return time >= start
        return time in start..end || time < start
    }

    /**
     * Locator used to navigate to and highlight the text in the publication
     */
    val syncTextLocator: Locator? by lazy {
        Url.invoke(textFile)?.let { href ->
            Locator(
                href,
                mediaType = MediaType.XHTML,
                title = title,
                locations = Locator.Locations(
                    listOf("#$textId"),
                    otherLocations = mapOf<String, Any>("cssSelector" to "#$textId"),
                    position = position,
                ),
            )
        }
    }

    /**
     * Locator meant to be sent via the audio-locator channel to the Flutter side
     *
     * NOTE: You might need to update the time fragment.
     */
    val flutterAudioLocator: Locator? by lazy {
        syncTextLocator?.let() { textLocator ->
            textLocator.copy(
                locations = textLocator.locations.copy(
                    fragments = listOf("t=${audioStart ?: 0.0}"),
                ),
            )
        }
    }

    /**
     * AudioLocator meant to be used for skipping to this item in the audio player.
     *
     * NOTE: You might need to update the time fragment.
     */
    val skipToAudioLocator: Locator? by lazy {
        Url.invoke(audioFile)?.let { href ->
            Locator(
                href,
                title = title,
                mediaType = audioMediaType,
                locations = Locator.Locations(
                    fragments = listOf("t=${audioStart ?: 0.0}"),
                ),
            )
        }
    }

    companion object {
        /**
         * Creates a [FlutterMediaOverlayItem] from a JSON object.
         * Returns null if the JSON object does not contain valid "audio" and "text"
         */
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
