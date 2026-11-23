/**
 * Picks the voice TTS uses when the app has not chosen one.
 *
 * Given only `utterance.lang`, Chrome takes the first installed voice for that
 * language. On macOS that is "Albert" for English, a novelty voice, so the
 * engine chooses a voice itself instead.
 */

import { isNoveltyVoice, isVeryLowQualityVoice } from "@readium/speech";

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
    // Novelty voices sing or whisper, and very low quality ones (Eloquence,
    // eSpeak) sound robotic. readium/speech keeps both lists, so they stay
    // current with the OS releases it tracks.
    return !isNoveltyVoice(voice.name, voice.voiceURI) && !isVeryLowQualityVoice(voice.name);
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

