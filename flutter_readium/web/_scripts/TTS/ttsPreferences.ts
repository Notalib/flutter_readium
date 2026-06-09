/**
 * Maps Dart TTSPreferences JSON to Web Speech API utterance properties.
 *
 * Dart fields:
 *   speed            -> utterance.rate    (0.1–10,  default 1.0)
 *   pitch            -> utterance.pitch   (0–2,     default 1.0)
 *   voiceIdentifier  -> SpeechSynthesisVoice matched by voiceURI
 *   languageOverride -> utterance.lang    (fallback when no voice matched)
 */
export interface WebTTSPreferences {
  rate: number;
  pitch: number;
  voice: SpeechSynthesisVoice | null;
  /** BCP-47 language override – applied when voice is null. */
  lang: string | null;
}

const DEFAULT_RATE = 1.0;
const DEFAULT_PITCH = 1.0;

/**
 * Returns a promise that resolves to the browser's voice list, waiting for the
 * `voiceschanged` event when the list is initially empty (required in Chrome).
 */
export function getAvailableVoicesAsync(): Promise<SpeechSynthesisVoice[]> {
  return new Promise((resolve) => {
    const voices = speechSynthesis.getVoices();
    if (voices.length > 0) {
      resolve(voices);
      return;
    }
    // Chrome loads voices asynchronously.
    const handler = () => {
      speechSynthesis.removeEventListener("voiceschanged", handler);
      resolve(speechSynthesis.getVoices());
    };
    speechSynthesis.addEventListener("voiceschanged", handler);
    // Fallback: resolve with empty list after 2 s so we never hang.
    setTimeout(() => {
      speechSynthesis.removeEventListener("voiceschanged", handler);
      resolve(speechSynthesis.getVoices());
    }, 2000);
  });
}

/**
 * Builds WebTTSPreferences from a Dart TTSPreferences JSON string.
 * Voice resolution is synchronous (call after voices are loaded).
 */
export function ttsPreferencesFromJson(json: Record<string, any>): WebTTSPreferences {
  const rate = typeof json.speed === "number" ? json.speed : DEFAULT_RATE;
  const pitch = typeof json.pitch === "number" ? json.pitch : DEFAULT_PITCH;

  const voiceId: string | null =
    typeof json.voiceIdentifier === "string" ? json.voiceIdentifier : null;
  const langOverride: string | null =
    typeof json.languageOverride === "string" ? json.languageOverride : null;

  let voice: SpeechSynthesisVoice | null = null;
  if (voiceId) {
    voice = speechSynthesis.getVoices().find((v) => v.voiceURI === voiceId) ?? null;
  }

  return { rate, pitch, voice, lang: langOverride };
}

/**
 * Serialises the browser voice list to a JSON string matching the Dart
 * ReaderTTSVoice schema.  Gender/quality are NOT emitted here — they are
 * enriched automatically by ReaderTTSVoiceUtils in the Dart platform-interface
 * layer using the bundled voices.json from https://readium.org/speech/.
 */
export async function serializeVoices(): Promise<string> {
  const voices = await getAvailableVoicesAsync();
  const result = voices.map((v) => ({
    identifier: v.voiceURI,
    name: v.name,
    language: v.lang,
    networkRequired: !v.localService,
  }));
  return JSON.stringify(result);
}
