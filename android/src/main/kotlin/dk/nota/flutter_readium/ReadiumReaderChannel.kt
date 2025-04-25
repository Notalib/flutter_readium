package dk.nota.flutter_readium

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.readium.r2.shared.publication.Locator

internal class ReadiumReaderChannel(messenger: BinaryMessenger, name: String) :
  MethodChannel(messenger, name) {
  fun onPageChanged(locator: Locator?) = invokeMethod("onPageChanged", locator?.toJSON().toString())
}
