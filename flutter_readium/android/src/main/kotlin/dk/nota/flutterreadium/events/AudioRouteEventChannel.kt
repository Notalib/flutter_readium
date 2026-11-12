package dk.nota.flutterreadium.events

import io.flutter.plugin.common.BinaryMessenger

/**
 * Registers the audio-route channel so Dart subscribers do not hit MissingPluginException.
 * AirPlay route reporting is iOS only, so this never emits.
 */
class AudioRouteEventChannel(
    messenger: BinaryMessenger,
) : EventChannelWrapper<Unit>(messenger, "dk.nota.flutter_readium/audio-route") {
    override fun sendEvent(data: Unit) = Unit
}
