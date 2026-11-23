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
 * Preference order: local voices, then the browser's default voice, then the
 * exact region, then high-quality voices. Each criterion outweighs all later
 * ones. Network voices (Chrome's "Google …", Edge's "… Online (Natural)") come
 * last: they send the book text to the vendor, fail offline, and Chrome's send
 * no word boundaries, so word highlighting stops working. Apps can still
 * choose one explicitly.
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
    (voice.localService ? 8 : 0) +
    (voice.default ? 4 : 0) +
    (normalizeLang(voice.lang) === wanted ? 2 : 0) +
    (HIGH_QUALITY_NAME.test(voice.name) ? 1 : 0);
  // Stable sort: equal scores keep the browser's order.
  return candidates.sort((a, b) => score(b) - score(a))[0];
}

/**
 * Resolves once the browser has listed its voices, or after `timeoutMs`.
 * Chrome returns an empty list from `getVoices()` until `voiceschanged` fires
 * shortly after page load, and without the list no default voice can be
 * picked.
 */
export function voicesLoaded(timeoutMs = 1000): Promise<void> {
  if (speechSynthesis.getVoices().length > 0) return Promise.resolve();
  return new Promise((resolve) => {
    const done = (): void => {
      clearTimeout(timer);
      speechSynthesis.removeEventListener("voiceschanged", done);
      resolve();
    };
    const timer = setTimeout(done, timeoutMs);
    speechSynthesis.addEventListener("voiceschanged", done);
  });
}

function normalizeLang(lang: string): string {
  return lang.replace("_", "-").toLowerCase();
}

/** "Eddy (English (United States))" -> "Eddy". */
function baseName(voiceName: string): string {
  const paren = voiceName.indexOf(" (");
  return paren === -1 ? voiceName : voiceName.slice(0, paren);
}
