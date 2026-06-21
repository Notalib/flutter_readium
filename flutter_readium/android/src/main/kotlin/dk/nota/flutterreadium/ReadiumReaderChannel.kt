package dk.nota.flutterreadium

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.AbsoluteUrl

internal class ReadiumReaderChannel(
    messenger: BinaryMessenger,
    name: String,
) : MethodChannel(messenger, name),
    CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) {
    fun onPageChanged(locator: Locator?) =
        launch {
            invokeMethod(
                "onPageChanged",
                locator?.toJSON().toString(),
            )
        }

    fun onExternalLinkActivated(url: AbsoluteUrl) = launch { invokeMethod("onExternalLinkActivated", url.toString()) }

    fun onTextSelected(
        locator: Locator,
        selectedText: String?,
    ) = launch {
        val json =
            JSONObject().apply {
                put("locator", locator.toJSON())
                put("selectedText", selectedText ?: JSONObject.NULL)
            }
        invokeMethod("onTextSelected", json.toString())
    }

    fun onSelectionAction(
        actionId: String,
        locator: Locator,
        selectedText: String?,
    ) = launch {
        val json =
            JSONObject().apply {
                put("actionId", actionId)
                put("locator", locator.toJSON())
                put("selectedText", selectedText ?: JSONObject.NULL)
            }
        invokeMethod("onSelectionAction", json.toString())
    }

    fun onImageTapped(json: String) = launch { invokeMethod("onImageTapped", json) }

    fun onDecorationInteraction(
        decorationId: String,
        group: String,
        type: String,
        locator: Locator?,
    ) = launch {
        val json =
            JSONObject().apply {
                put("decorationId", decorationId)
                put("group", group)
                put("type", type)
                if (locator != null) put("locator", locator.toJSON()) else put("locator", JSONObject.NULL)
            }
        invokeMethod("onDecorationInteraction", json.toString())
    }
}
