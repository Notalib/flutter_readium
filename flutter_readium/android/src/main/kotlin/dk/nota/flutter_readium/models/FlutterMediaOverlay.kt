package dk.nota.flutter_readium.models

import android.os.Parcelable
import android.util.Log
import dk.nota.flutter_readium.getTextId
import dk.nota.flutter_readium.progression
import kotlinx.parcelize.IgnoredOnParcel
import kotlinx.parcelize.Parcelize
import org.json.JSONArray
import org.json.JSONObject
import org.readium.r2.navigator.extensions.time
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import kotlin.time.Duration

private const val TAG = "FlutterMediaOverlay"

/**
 * Simple media overlay mapping.
 */
@Parcelize
data class FlutterMediaOverlay(
    val items: List<FlutterMediaOverlayItem>,
) : Parcelable {
    /**
     * The audio file name (without fragment).
     */
    private val audioFile
        get() = items.firstOrNull()?.audioFile ?: ""

    /**
     * The text file name (without fragment).
     */
    @IgnoredOnParcel
    private val textFile
        get() = items.firstOrNull()?.textFile ?: ""

    /**
     * The audio file Url.
     */
    private val audioUrl
        get() = Url.invoke(audioFile)

    /**
     * The text file Url.
     */
    private val textUrl
        get() = Url.invoke(textFile)

    /**
     * The total duration of the audio, based on the end time of the last item.
     */
    val duration
        get() = items.lastOrNull()?.audioEnd ?: 0.0

    /**
     * Find the media overlay item for the given file and time.
     * Returns null if no item is found.
     */
    fun findItemInRange(
        fileHref: Url,
        time: Double,
    ): FlutterMediaOverlayItem? = findItemInRange(fileHref.toString(), time)

    /**
     * Find the media overlay item for the given file and time.
     * Returns null if no item is found.
     */
    fun findItemInRange(
        fileHref: Url,
        duration: Duration,
    ): FlutterMediaOverlayItem? = findItemInRange(fileHref, duration.inWholeSeconds.toDouble())

    /**
     * Find the media overlay item for the given file and time.
     * Returns null if no item is found.
     */
    fun findItemInRange(
        fileHref: String,
        duration: Duration,
    ): FlutterMediaOverlayItem? = findItemInRange(fileHref, duration.inWholeSeconds.toDouble())

    /**
     * Find the media overlay item for the given file and time.
     * Returns null if no item is found.
     */
    fun findItemInRange(
        fileHref: String,
        time: Double,
    ): FlutterMediaOverlayItem? {
        val href = Url.invoke(fileHref) ?: return null
        if (!href.isEquivalent(textUrl) && !href.isEquivalent(audioUrl)) {
            return null
        }

        return items.firstOrNull { item -> item.isInRange(href, time) }
    }

    /**
     * Find the media overlay item from the text reference.
     */
    fun findItemFromTextId(
        href: Url,
        textId: String,
    ): FlutterMediaOverlayItem? {
        if (!href.isEquivalent(textUrl) && !href.isEquivalent(audioUrl)) {
            return null
        }

        return items.firstOrNull { item -> item.textId == textId }
    }

    /**
     * Find the media overlay item from the given locator.
     * A locator can either be an audio+time based locator or a text+id based locator.
     * This allows us to map back and forth between audio and text.
     */
    @OptIn(InternalReadiumApi::class)
    fun findItemFromLocator(locator: Locator): FlutterMediaOverlayItem? {
        val href = locator.href
        if (!href.isEquivalent(Url.invoke(textFile)) && !href.isEquivalent(Url.invoke(audioFile))) {
            return null
        }

        locator.locations.time?.let { timeOffset ->
            return findItemInRange(href, timeOffset)
        }

        locator.getTextId()?.let { textId ->
            return findItemFromTextId(href, textId)
        }

        locator.progression?.let { progression ->
            val item = items.firstOrNull { item -> item.isInProgression(href, progression) }

            // FIXME: This item?skipToAudioLocator will have an incorrect time value, since it is the original audioStart and not calculated from progression.
            return item
        }

        if (locator.locations.fragments.isEmpty() && locator.mediaType.isHtml) {
            // If there is no fragment, and it is a HTML locator, we return the first item for the href
            Log.d(
                TAG,
                "::findItemFromLocator - no fragment in locator of type HTML, returning first item for href=${href.path}",
            )
            return items.firstOrNull { item ->
                item.textFile == href.path
            }
        }

        Log.d(
            TAG,
            "::findItemFromLocator - no time or textId in locator, cannot find item for locator=$locator",
        )

        return null
    }

    companion object {
        fun fromJson(
            json: JSONObject,
            position: Int,
            tocHref: Url?,
            title: String,
            readiumOrderItemDuration: Double,
        ): FlutterMediaOverlay? {
            val topNarration = json.opt("narration") as? JSONArray ?: return null
            val items = mutableListOf<FlutterMediaOverlayItem>()
            for (i in 0 until topNarration.length()) {
                val itemJson = topNarration.getJSONObject(i)
                FlutterMediaOverlayItem
                    .fromJson(
                        itemJson,
                        position,
                        tocHref,
                        title,
                        readiumOrderItemDuration,
                    )?.let { items.add(it) }

                fromJson(
                    itemJson,
                    position,
                    tocHref,
                    title,
                    readiumOrderItemDuration,
                )?.let { items.addAll(it.items) }
            }

            return FlutterMediaOverlay(items)
        }
    }
}
