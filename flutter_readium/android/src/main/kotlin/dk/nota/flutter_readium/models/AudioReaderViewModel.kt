package dk.nota.flutter_readium.models

import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.navigator.media.audio.AudioNavigatorFactory

open class AudioReaderViewModel : ReaderViewModel() {
    var preferences: ExoPlayerPreferences? = null

}
