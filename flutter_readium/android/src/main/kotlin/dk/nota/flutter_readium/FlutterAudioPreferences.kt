package dk.nota.flutter_readium

import kotlinx.serialization.Serializable
import org.json.JSONObject
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.r2.navigator.preferences.Configurable

@Serializable
data class FlutterAudioPreferences(
    val volume: Double? = null,
    val pitch: Double? = null,
    val speed: Double? = null,
    val seekInterval: Double = 30.0,
    val controlPanelInfoType: ControlPanelInfoType? = ControlPanelInfoType.STANDARD,
) : Configurable.Preferences<FlutterAudioPreferences> {

    override fun plus(other: FlutterAudioPreferences): FlutterAudioPreferences =
        FlutterAudioPreferences(
            volume = other.volume ?: volume,
            pitch = other.pitch ?: pitch,
            speed = other.speed ?: speed,
            seekInterval = other.seekInterval,
            controlPanelInfoType = other.controlPanelInfoType
        )

    fun toExoPlayerPreferences(): ExoPlayerPreferences {
        return ExoPlayerPreferences(
            pitch = this.pitch,
            speed = this.speed
        )
    }

    companion object {
        fun fromJSON(json: String): FlutterAudioPreferences {
            return fromJSON(JSONObject(json))
        }

        fun fromJSON(jsonObject: JSONObject): FlutterAudioPreferences {
            return FlutterAudioPreferences(
                volume = jsonObject.getDouble("volume"),
                pitch = jsonObject.getDouble("pitch"),
                speed = jsonObject.getDouble("speed"),
                seekInterval = jsonObject.getDouble("seekInterval"),
                controlPanelInfoType = ControlPanelInfoType.fromString( jsonObject.getString("controlPanelInfoType"))
            )
        }

        fun toJSON(preferences: FlutterAudioPreferences): JSONObject {
            val jsonObject = JSONObject()
            jsonObject.put("volume", preferences.volume)
            jsonObject.put("pitch", preferences.pitch)
            jsonObject.put("speed", preferences.speed)
            jsonObject.put("seekInterval", preferences.seekInterval)
            jsonObject.put("controlPanelInfoType", preferences.controlPanelInfoType?.toString())
            return jsonObject
        }

        fun fromMap(prefs: Map<*, *>): FlutterAudioPreferences {
            return FlutterAudioPreferences(
                volume = prefs["volume"] as? Double ?: 1.0,
                pitch = prefs["pitch"] as? Double ?: 1.0,
                speed = prefs["speed"] as? Double ?: 1.0,
                seekInterval = prefs["seekInterval"] as? Double ?: 30.0,
                // TODO: Not sure if this is correct
                controlPanelInfoType = ControlPanelInfoType.fromString( prefs["controlPanelInfoType"] as? String ?: "standard"),
            )
        }
    }
}
