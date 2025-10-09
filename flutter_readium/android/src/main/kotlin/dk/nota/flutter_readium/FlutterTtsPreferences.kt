package dk.nota.flutter_readium

import kotlinx.serialization.Serializable
import org.json.JSONObject
import org.readium.navigator.media.tts.android.AndroidTtsEngine
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.util.Language

@Serializable
data class FlutterTtsPreferences(
    val language: String? = null,
    val pitch: Double? = null,
    val speed: Double? = null,
    val voices: Map<String, String>? = null,
    val controlPanelInfoType: ControlPanelInfoType? = ControlPanelInfoType.STANDARD,
) {
    @OptIn(ExperimentalReadiumApi::class)
    fun toAndroidTtsPreferences(): AndroidTtsPreferences {
        return AndroidTtsPreferences(
            language = language?.let { Language(it) },
            pitch = pitch,
            speed = speed,
            voices = voices?.map { (lang, id) -> Language(lang) to AndroidTtsEngine.Voice.Id(id) }
                ?.toMap()
        )
    }

    fun plus(other: FlutterTtsPreferences): FlutterTtsPreferences =
        FlutterTtsPreferences(
            language = other.language ?: language,
            pitch = other.pitch ?: pitch,
            speed = other.speed ?: speed,
            voices = other.voices ?: voices,
            controlPanelInfoType = other.controlPanelInfoType ?: controlPanelInfoType
        )

    companion object {
        fun fromJSON(json: String): FlutterTtsPreferences {
            return fromJSON(JSONObject(json))
        }

        fun fromJSON(jsonObject: JSONObject): FlutterTtsPreferences {
            val voicesMap = mutableMapOf<String, String>()
            if (jsonObject.has("voices")) {
                val voicesJson = jsonObject.getJSONObject("voices")
                for (key in voicesJson.keys()) {
                    voicesMap[key] = voicesJson.getString(key)
                }
            }
            return FlutterTtsPreferences(
                language = jsonObject.optString("language", null),
                pitch = jsonObject.optDouble("pitch").let { if (it.isNaN()) null else it },
                speed = jsonObject.optDouble("speed").let { if (it.isNaN()) null else it },
                voices = voicesMap.ifEmpty { null },
                controlPanelInfoType = ControlPanelInfoType.fromString(
                    jsonObject.optString(
                        "controlPanelInfoType",
                        "standard"
                    )
                )
            )
        }

        fun toJSON(preferences: FlutterTtsPreferences): JSONObject {
            val jsonObject = JSONObject()
            jsonObject.put("language", preferences.language)
            jsonObject.put("pitch", preferences.pitch)
            jsonObject.put("speed", preferences.speed)
            preferences.voices?.let { voices ->
                val voicesJson = JSONObject()
                voices.forEach { (key, value) -> voicesJson.put(key, value) }
                jsonObject.put("voices", voicesJson)
            }
            jsonObject.put("controlPanelInfoType", preferences.controlPanelInfoType?.toString())
            return jsonObject
        }

        fun fromMap(prefs: Map<*, *>?): FlutterTtsPreferences {
            val voices = (prefs?.get("voices") as? Map<*, *>)?.mapNotNull {
                val key = it.key as? String
                val value = it.value as? String
                if (key != null && value != null) key to value else null
            }?.toMap()
            return FlutterTtsPreferences(
                language = prefs?.get("language") as? String,
                pitch = prefs?.get("pitch") as? Double,
                speed = prefs?.get("speed") as? Double,
                voices = voices,
                controlPanelInfoType = ControlPanelInfoType.fromString(
                    prefs?.get("controlPanelInfoType") as? String ?: "standard"
                )
            )
        }
    }
}
