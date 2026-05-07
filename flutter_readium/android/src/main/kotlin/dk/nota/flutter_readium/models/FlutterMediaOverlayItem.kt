package dk.nota.flutter_readium.models

import android.os.Parcelable
import dk.nota.flutter_readium.copyWithTimeFragment
import dk.nota.flutter_readium.copyWithTocHref
import dk.nota.flutter_readium.letIfBothNotNull
import kotlinx.parcelize.IgnoredOnParcel
import kotlinx.parcelize.Parcelize
import org.json.JSONObject
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType

/**
 * A single media overlay item mapping audio to text.
 */
@Parcelize
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
     * The ToC item for this item.
     */
    val tocHref: Url?,
    /**
     * The title of the chapter or section this item belongs to
     */
    val title: String,
    /**
     * Known duration of the reading order item. Needed to find items from a locator's progression
     * value and to calculate an updated time fragment.
     */
    val readingOrderItemDuration: Double,
) : Parcelable {
    /**
     * The audio file without the fragment (e.g. "chapter1.mp3")
     */
    val audioFile
        get() = audio.substringBefore("#")

    /**
     * The media type of the audio file
     */
    val audioMediaType
        get() =
            when (audioFile.split('.').lastOrNull()) {
                "mp3" -> MediaType.MP3
                "opus" -> MediaType.OPUS
                else -> MediaType.MP3
            }

    /**
     * The text file without the fragment (e.g. "chapter1.html")
     */
    val textFile
        get() = text.substringBefore("#")

    /**
     * The text fragment identifier (e.g. "para34"), or empty string if none
     */
    val textId
        get() = text.substringAfter("#", "")

    private val audioFragment
        get() = audio.substringAfter("#", "")

    /**
     * The audio time fragment minus the t= (e.g. "12.34,15.67"), or null if none
     */
    private val audioTime
        get() =
            if (audioFragment.startsWith("t=")) audioFragment.substringAfter("t=") else null

    /**
     * The start time in seconds, or null if none
     */
    val audioStart: Double?
        get() = audioTime?.substringBefore(",")?.toDoubleOrNull()

    /**
     * Start progression of this segment, e.g. percentages into the audio file, between 0 and 1.
     */
    val progressionStart: Double?
        get() =
            letIfBothNotNull(
                audioStart,
                readingOrderItemDuration.takeIf { it > 0.0 },
            )?.let { (start, riDuration) -> start / riDuration }

    /**
     * End progression of this segment, e.g. percentages into the audio file, between 0 and 1
     */
    val progressionEnd: Double?
        get() =
            letIfBothNotNull(
                audioEnd,
                readingOrderItemDuration.takeIf { it > 0.0 },
            )?.let { (end, riDuration) -> end / riDuration }

    /**
     * The end time in seconds, or null if none
     */
    val audioEnd: Double?
        get() = audioTime?.substringAfter(",")?.toDoubleOrNull()

    /**
     * The duration of the segment.
     */
    val duration: Double?
        get() =
            letIfBothNotNull(audioEnd, audioStart)?.let { (end, start) -> end - start }

    /**
     * Is this item in range for the given file reference and time offset?
     */
    fun isInRange(
        fileRef: Url,
        time: Double,
    ): Boolean {
        if (!fileRef.isEquivalent(Url.invoke(textFile))) {
            if (!fileRef.isEquivalent(Url.invoke(audioFile))) {
                return false
            }
        }

        val start = audioStart ?: return false
        val end = audioEnd ?: return time >= start // No end value, check if time is after start.
        return time in start..end || time < start
    }

    /**
     * Is this item within range of the given progression?
     */
    fun isInProgression(
        fileRef: Url,
        progression: Double,
    ): Boolean {
        if (!fileRef.isEquivalent(Url.invoke(textFile))) {
            if (!fileRef.isEquivalent(Url.invoke(audioFile))) {
                return false
            }
        }

        val start = progressionStart ?: return false
        val end =
            progressionEnd
                ?: return progression >= start // No end value, check if progress is after start.
        return progression in start..end
    }

    /**
     * Locator used to navigate to and highlight the text in the publication
     */
    @IgnoredOnParcel
    val syncTextLocator: Locator? by lazy {
        Url.invoke(textFile)?.let { href ->
            Locator(
                href,
                mediaType = MediaType.XHTML,
                title = title,
                locations =
                    Locator.Locations(
                        listOf("#$textId"),
                        otherLocations = mapOf("cssSelector" to "#$textId"),
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
    @IgnoredOnParcel
    val flutterAudioLocator: Locator? by lazy {
        syncTextLocator?.copyWithTimeFragment(audioStart ?: 0.0)?.copyWithTocHref(tocHref)
    }

    /**
     * AudioLocator meant to be used for skipping to this item in the audio player.
     *
     * NOTE: You might need to update the time fragment.
     */
    @IgnoredOnParcel
    val skipToAudioLocator: Locator? by lazy {
        Url.invoke(audioFile)?.let { href ->
            Locator(
                href,
                title = title,
                mediaType = audioMediaType,
                locations =
                    Locator.Locations(
                        fragments = listOf("t=${audioStart?.toInt() ?: 0}"),
                    ),
            )
        }
    }

    companion object {
        /**
         * Creates a [FlutterMediaOverlayItem] from a JSON object.
         * Returns null if the JSON object does not contain valid "audio" and "text"
         */
        fun fromJson(
            json: JSONObject,
            position: Int,
            tocHref: Url?,
            title: String,
            readiumOrderItemDuration: Double,
        ): FlutterMediaOverlayItem? {
            val audio = json.optString("audio")
            val text = json.optString("text")
            return if (audio != "" && text != "") {
                FlutterMediaOverlayItem(
                    audio,
                    text,
                    position,
                    tocHref,
                    title,
                    readiumOrderItemDuration,
                )
            } else {
                null
            }
        }
    }
}
