package dk.nota.flutterreadium.models

import android.os.Parcelable
import dk.nota.flutterreadium.PluginLog
import dk.nota.flutterreadium.getTextId
import dk.nota.flutterreadium.progression
import dk.nota.flutterreadium.toSeconds
import kotlinx.parcelize.IgnoredOnParcel
import kotlinx.parcelize.Parcelize
import org.json.JSONArray
import org.json.JSONObject
import org.readium.r2.navigator.extensions.time
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link
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
        time: Duration,
    ): FlutterMediaOverlayItem? = findItemInRange(fileHref, time.toSeconds)

    /**
     * Find the media overlay item for the given file and time.
     * Returns null if no item is found.
     */
    fun findItemInRange(
        fileHref: String,
        duration: Duration,
    ): FlutterMediaOverlayItem? = findItemInRange(fileHref, duration.toSeconds)

    /**
     * Find the media overlay item for the given file and time.
     * Returns null if no item is found.
     */
    fun findItemInRange(
        fileHref: String,
        time: Double,
    ): FlutterMediaOverlayItem? {
        val href = Url.invoke(fileHref) ?: return null

        val current = items.firstOrNull { item -> item.isInRange(href, time) }
        if (current != null) return current

        return items.firstOrNull { item ->
            val matchesResource =
                href.isEquivalent(Url.invoke(item.audioFile)) ||
                    href.isEquivalent(Url.invoke(item.textFile))
            val start = item.audioStart

            matchesResource && start != null && time < start
        }
    }

    /**
     * Find the media overlay item from the text reference.
     */
    fun findItemFromTextId(
        href: Url,
        textId: String,
    ): FlutterMediaOverlayItem? =
        items.firstOrNull { item ->
            item.textId == textId && href.isEquivalent(Url.invoke(item.textFile))
        }

    /**
     * Find the first media overlay item assigned to the given ToC text reference.
     */
    fun findItemFromTocHref(
        href: Url,
        textId: String,
    ): FlutterMediaOverlayItem? {
        return items.firstOrNull { item ->
            val tocHref = item.tocHref ?: return@firstOrNull false
            tocHref.fragment == textId && href.isEquivalent(tocHref.removeFragment())
        }
    }

    fun withTocTitles(toc: List<Link>): FlutterMediaOverlay =
        copy(
            items =
                items.map { item ->
                    val match = toc.firstOrNull { item.tocHref?.isEquivalent(it.href.resolve()) == true }
                    if (match == null) item else item.copy(title = match.title ?: "", tocHref = match.href.resolve())
                },
        )

    /**
     * Find the media overlay item from the given locator.
     * A locator can either be an audio+time based locator or a text+id based locator.
     * This allows us to map back and forth between audio and text.
     *
     * [allowResourceFallback] gates the *imprecise* resource-first fallbacks (an
     * unmatched text id, or no id at all on an HTML resource): when true, an uncued
     * anchor maps to the first cue of the resource; when false, returns null so the
     * caller can leave playback untouched. Pass false when audio is already playing
     * in this same resource (cross-resource check is done at the navigator level).
     * See issue #139.
     */
    @OptIn(InternalReadiumApi::class)
    fun findItemFromLocator(
        locator: Locator,
        allowResourceFallback: Boolean = true,
    ): FlutterMediaOverlayItem? {
        val href = locator.href

        locator.locations.time?.let { timeOffset ->
            return findItemInRange(href, timeOffset)
        }

        // DiViNa comic page: the page locator's only anchor is a generic "img" css selector
        // (which getTextId() would otherwise pick up), not a media-overlay text id. Match the
        // page's first narrated item by href — the textref is the image itself.
        if (locator.mediaType.isBitmap) {
            return items.firstOrNull { item -> item.textFile == href.path }
        }

        // Reflowable text: try exact DOM element id match first; fall through on no match.
        locator.getTextId()?.let { textId ->
            val exactItem = findItemFromTextId(href, textId)
            if (exactItem != null) return exactItem
            findItemFromTocHref(href, textId)?.let { return it }
            PluginLog.d(TAG, "::findItemFromLocator - textId '$textId' matched no cue for href=${href.path}")
        }

        locator.progression?.let { progression ->
            val item = items.firstOrNull { item -> item.isInProgression(href, progression) }

            // FIXME: This item?skipToAudioLocator will have an incorrect time value, since it is the original audioStart and not calculated from progression.
            return item
        }

        if (allowResourceFallback && locator.mediaType.isHtml) {
            // No cue matched — fall back to first item of the resource (covers both
            // no-fragment HTML and an id that has no narration entry e.g. a heading).
            PluginLog.d(
                TAG,
                "::findItemFromLocator - resource-fallback: first item for href=${href.path}",
            )
            return items.firstOrNull { item ->
                item.textFile == href.path
            }
        }

        PluginLog.d(
            TAG,
            "::findItemFromLocator - no match for locator=$locator",
        )

        return null
    }

    /**
     * Flattens narration with resource-bound section inheritance and local heading continuation.
     */
    companion object {
        fun fromJson(
            json: JSONObject,
            position: Int,
            tocHref: Url?,
            title: String,
            readiumOrderItemDuration: Double,
            tocHrefs: List<Url> = emptyList(),
        ): FlutterMediaOverlay? {
            val topNarration = json.opt("narration") as? JSONArray ?: return null
            val items = mutableListOf<FlutterMediaOverlayItem>()
            var currentTocHref = tocHref

            for (i in 0 until topNarration.length()) {
                val obj = topNarration.getJSONObject(i)
                val text = obj.optString("text").takeIf { it.isNotEmpty() }?.let { Url(it) }
                val textFile = text?.removeFragment()
                // Boundary page cues can reference the next file inside the previous file's container.
                if (textFile != null && currentTocHref?.removeFragment()?.isEquivalent(textFile) != true) {
                    currentTocHref = tocHrefs.firstOrNull { it.isEquivalent(textFile) }
                }
                val matchingTocHref = text?.let { href -> tocHrefs.firstOrNull { it.isEquivalent(href) } }
                val nodeTocHref = matchingTocHref ?: currentTocHref
                val hasChildren = (obj.optJSONArray("narration")?.length() ?: 0) > 0

                FlutterMediaOverlayItem
                    .fromJson(
                        obj,
                        position,
                        nodeTocHref,
                        title,
                        readiumOrderItemDuration,
                    )?.let { item ->
                        items.add(item)
                        if (!hasChildren && matchingTocHref != null) currentTocHref = matchingTocHref
                    }
                fromJson(obj, position, nodeTocHref, title, readiumOrderItemDuration, tocHrefs)
                    ?.let { items.addAll(it.items) }
            }
            return FlutterMediaOverlay(items)
        }
    }
}
