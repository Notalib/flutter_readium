package dk.nota.flutter_readium.models

import dk.nota.flutter_readium.jsonDecode
import org.json.JSONObject
import org.readium.r2.shared.InternalReadiumApi

class ViewPortSize(
    val width: Int,
    val height: Int,
    val scrollTop: Int,
    val scrollHeight: Int,
    val scrollLeft: Int,
    val scrollWidth: Int,
    val scrollMode: Boolean
) {
    val prevProgression: Double
        get() = if (scrollMode) (scrollTop.toDouble() - height.toDouble()) / scrollHeight.toDouble() else (scrollLeft.toDouble() - width.toDouble()) / scrollWidth.toDouble()

    val progression: Double
        get() = if (scrollMode) scrollTop.toDouble() / scrollHeight.toDouble() else scrollLeft.toDouble() / scrollWidth.toDouble()

    val nextProgression: Double
        get() = if (scrollMode) (scrollTop.toDouble() + height.toDouble()) / scrollHeight.toDouble() else (scrollLeft.toDouble() + width.toDouble()) / scrollWidth.toDouble()

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
