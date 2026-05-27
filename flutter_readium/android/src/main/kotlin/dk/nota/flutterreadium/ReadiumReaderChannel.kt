package dk.nota.flutterreadium

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
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
}
