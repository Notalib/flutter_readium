package dk.nota.flutter_readium

import kotlinx.serialization.Serializable
import org.json.JSONObject
import org.readium.navigator.media.tts.android.AndroidTtsEngine
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.extensions.optNullableString
import org.readium.r2.shared.util.Language

/**
 * TTS preferences used in the Flutter Readium plugin.
 */
@Serializable
data class FlutterTtsPreferences(
    val language: String? = null,
    val pitch: Double? = null,
    val speed: Double? = null,
    val voices: Map<String, String>? = null,
    val controlPanelInfoType: ControlPanelInfoType? = ControlPanelInfoType.STANDARD,
) {
    /**
     * Convert to AndroidTtsPreferences.
     */
    @OptIn(ExperimentalReadiumApi::class)
    fun toAndroidTtsPreferences(): AndroidTtsPreferences {
        val androidVoices =
            voices?.map { (lang, id) -> Language(lang) to AndroidTtsEngine.Voice.Id(id) }
                ?.toMap()

        // If no language in preferences, use the first language of the preferred voices.
        val androidLanguage =
            language?.let { Language(it) } ?: androidVoices?.firstNotNullOfOrNull { it.key }
        return AndroidTtsPreferences(
            language = androidLanguage,
            pitch = pitch,
            speed = speed,
            voices = androidVoices
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
        /**
         * Create FlutterTtsPreferences from JSON string.
         */
        fun fromJSON(json: String): FlutterTtsPreferences {
            return fromJSON(JSONObject(json))
        }

        /**
         * Create FlutterTtsPreferences from JSON object.
         */
        @OptIn(InternalReadiumApi::class)
        fun fromJSON(jsonObject: JSONObject): FlutterTtsPreferences {
            val voicesMap = mutableMapOf<String, String>()
            if (jsonObject.has("voices")) {
                val voicesJson = jsonObject.getJSONObject("voices")
                for (key in voicesJson.keys()) {
                    voicesMap[key] = voicesJson.getString(key)
                }
            }
            return FlutterTtsPreferences(
                language = jsonObject.optNullableString("language"),
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

        /**
         * Convert FlutterTtsPreferences to JSON object.
         */
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

        /**
         * Create FlutterTtsPreferences from a map.
         */
        @OptIn(ExperimentalReadiumApi::class)
        fun fromMap(
            ttsPrefs: Map<*, *>?,
            androidVoices: Set<AndroidTtsEngine.Voice>
        ): FlutterTtsPreferences {
            val voices = mutableMapOf<String, String>()

            ttsPrefs?.let { prefs ->
                (prefs["voiceIdentifier"] as? String)?.let { voiceId ->
                    androidVoices.firstOrNull {
                        it.id.value.equals(voiceId, true)
                    }?.let {
                        voices[it.language.code] = it.id.value
                    }
                }

                (prefs["voices"] as? Map<*, *>?)?.forEach {
                    val key = it.key as? String
                    val value = it.value as? String
                    if (key != null && value != null) {
                        voices[key] = value
                    }
                }
            }

            return FlutterTtsPreferences(
                language = ttsPrefs?.get("language") as? String,
                pitch = ttsPrefs?.get("pitch") as? Double,
                speed = ttsPrefs?.get("speed") as? Double,
                voices = voices,
                controlPanelInfoType = ControlPanelInfoType.fromString(
                    ttsPrefs?.get("controlPanelInfoType") as? String ?: "standard"
                )
            )
        }
    }
}
