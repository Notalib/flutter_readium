package dk.nota.flutter_readium.models

import dk.nota.flutter_readium.jsonDecode
import org.json.JSONObject
import org.readium.r2.shared.InternalReadiumApi

/**
 * Viewport information. Retrieved from javascript via window.flutterReadium.getViewPortSize().
 */
class ViewPortSize(
    /**
     * Viewport width
     */
    val width: Int,

    /**
     * Viewport height
     */
    val height: Int,

    /**
     * Vertical scroll offset
     */
    val scrollTop: Int,

    /**
     * Vertical scroll height, e.g. how much can we scroll vertically.
     */
    val scrollHeight: Int,

    /**
     * Horizontal scroll offset
     */
    val scrollLeft: Int,

    /**
     * Horizontal scroll width, e.g. how much can we scroll horizontally.
     */
    val scrollWidth: Int,

    /**
     * Scroll mode? If true, vertical scroll mode is enabled.
     */
    val scrollMode: Boolean
) {
    /**
     * What is the previous progression, if we are scrolling backwards?
     */
    val prevProgression: Double
        get() = if (scrollMode) (scrollTop.toDouble() - height.toDouble()) / scrollHeight.toDouble() else (scrollLeft.toDouble() - width.toDouble()) / scrollWidth.toDouble()

    /**
     * What is the current progression? E.g top of the viewport?
     */
    val progression: Double
        get() = if (scrollMode) scrollTop.toDouble() / scrollHeight.toDouble() else scrollLeft.toDouble() / scrollWidth.toDouble()

    /**
     * What is the current bottom progression? E.g. the end of the viewport?
     *
     * This is needed to determine, if we need to scroll to the next file in the readingOrder.
     */
    val endProgression: Double
        get() = if (scrollMode) (scrollTop.toDouble() + height.toDouble()) / scrollHeight.toDouble() else (scrollLeft.toDouble() + width.toDouble()) / scrollWidth.toDouble()

    /**
     * Next progression, if we're scrolling forwards.
     *
     * If we reach >1.0 and [endProgression] is 1.0, we need to go to the next file in the readingOrder.
     */
    val nextProgression: Double
        get() = if (scrollMode) (scrollTop.toDouble() + height.toDouble()) / scrollHeight.toDouble() else (scrollLeft.toDouble() + width.toDouble()) / scrollWidth.toDouble()

    /**
     * Number of pages as calculated from the viewport size.
     */
    val numberOfPages: Double
        get() = if (scrollMode) scrollHeight.toDouble() / height.toDouble() else scrollWidth.toDouble() / width.toDouble()

    companion object {
        fun fromJson(json: String, scrollMode: Boolean): ViewPortSize =
            fromJson(jsonDecode(json) as JSONObject, scrollMode)

        @OptIn(InternalReadiumApi::class)
        fun fromJson(jsonObject: JSONObject, scrollMode: Boolean): ViewPortSize {

            val height = jsonObject.optInt("height")
            val width = jsonObject.optInt("width")
            val scrollHeight = jsonObject.optInt("scrollHeight")
            val scrollTop = jsonObject.optInt("scrollTop")
            val scrollWidth = jsonObject.optInt("scrollWidth")
            val scrollLeft = jsonObject.optInt("scrollLeft")

            return ViewPortSize(
                height = height,
                width = width,
                scrollTop = scrollTop,
                scrollHeight = scrollHeight,
                scrollLeft = scrollLeft,
                scrollWidth = scrollWidth,
                scrollMode = scrollMode
            )
        }
    }
}
