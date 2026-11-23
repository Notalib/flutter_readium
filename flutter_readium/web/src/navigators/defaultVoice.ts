/**
 * Picks the voice TTS uses when the app has not chosen one.
 *
 * Given only `utterance.lang`, Chrome takes the first installed voice for that
 * language. On macOS that is "Albert" for English, a novelty voice, so the
 * engine chooses a voice itself instead.
 */

/**
 * macOS novelty voices and the old Eloquence voices (Eddy, Flo, ...). They are
 * robotic or sing, and are never a sensible default. Names follow the
 * novelty and veryLowQuality filters in https://github.com/readium/speech.
 */
const UNSUITABLE_VOICE_NAMES = new Set([
  "Albert", "Bad News", "Bahh", "Bells", "Boing", "Bubbles", "Cellos", "Fred", "Good News",
  "Jester", "Junior", "Kathy", "Organ", "Ralph", "Superstar", "Trinoids", "Whisper", "Wobble",
  "Zarvox",
  "Eddy", "Flo", "Grandma", "Grandpa", "Reed", "Rocko", "Sandy", "Shelley",
]);

/** Marks the higher-quality downloads of macOS, Windows and Edge voices. */
const HIGH_QUALITY_NAME = /\((Premium|Enhanced)\)|\bNatural\b/;

/**
 * Returns the best installed voice for `lang` (a BCP 47 tag such as "da" or
 * "en-US"), or undefined when there is none.
 *
 * Preference order: the browser's default voice when it speaks the language,
 * then a voice for the exact region, then high-quality voices, then local
 * voices. Local voices come before network ones because Chrome's network
 * voices send no word boundaries, so word highlighting stops working.
 */
export function pickDefaultVoice(
  voices: SpeechSynthesisVoice[],
  lang: string
): SpeechSynthesisVoice | undefined {
  const wanted = normalizeLang(lang);
  const primary = wanted.split("-")[0];
  const candidates = voices.filter((voice) => {
    const voiceLang = normalizeLang(voice.lang);
    if (voiceLang !== wanted && voiceLang.split("-")[0] !== primary) return false;
    return !UNSUITABLE_VOICE_NAMES.has(baseName(voice.name));
  });
  const score = (voice: SpeechSynthesisVoice): number =>
    (voice.default ? 8 : 0) +
    (normalizeLang(voice.lang) === wanted ? 4 : 0) +
    (HIGH_QUALITY_NAME.test(voice.name) ? 2 : 0) +
    (voice.localService ? 1 : 0);
  // Stable sort: equal scores keep the browser's order.
  return candidates.sort((a, b) => score(b) - score(a))[0];
}

function normalizeLang(lang: string): string {
  return lang.replace("_", "-").toLowerCase();
}

/** "Eddy (English (United States))" -> "Eddy". */
function baseName(voiceName: string): string {
  const paren = voiceName.indexOf(" (");
  return paren === -1 ? voiceName : voiceName.slice(0, paren);
}
