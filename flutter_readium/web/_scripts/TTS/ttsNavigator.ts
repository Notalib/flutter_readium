/**
 * WebTTSEngine — web TTS implementation using the browser's SpeechSynthesis API.
 *
 * Responsibilities:
 *  - Walk EPUB/WebPub text via PublicationContentIterator + HTMLResourceContentIterator.
 *  - Speak each TextElement via SpeechSynthesisUtterance.
 *  - Emit state payloads to window.updateTimebasedPlayerState (same contract as AudioNavigator).
 *  - Emit locator updates to window.updateTextLocator for position bookmarking.
 *  - Navigate the visual navigator to the current paragraph on each utterance start.
 *
 * Known limitations:
 *  - TODO(#209): TTS word/sentence highlighting is deferred until the ts-toolkit Decorator
 *    API (PR #209) merges.  Locators are emitted to Dart for bookmarking but no visual
 *    highlight is applied inside the EPUB iframe.
 *  - onboundary sub-utterance granularity is not available in all browsers (Firefox, some
 *    mobile).  When absent, the engine falls back to utterance (paragraph) level silently.
 */

import { EpubNavigator, WebPubNavigator } from "@readium/navigator";
import {
  ContentElement,
  HTMLResourceContentIterator,
  Locator,
  PublicationContentIterator,
  TextElement,
} from "@readium/shared";
import { ReadiumPublication } from "../extensions/ReadiumPublication";
import {
  WebTTSPreferences,
  serializeVoices,
  ttsPreferencesFromJson,
} from "./ttsPreferences";

/** Minimum ms between onboundary state emissions (throttle). */
const BOUNDARY_THROTTLE_MS = 100;

type AnyNavigator = EpubNavigator | WebPubNavigator;

/** JSON payload shape matching ReadiumTimebasedState. */
function buildTTSStatePayload(
  state: string,
  locator: Locator | null
): string {
  return JSON.stringify({
    state,
    currentOffset: null,
    currentDuration: null,
    currentLocator: locator ? JSON.parse(JSON.stringify(locator)) : null,
  });
}

function emitState(state: string, locator: Locator | null) {
  (window as any).updateTimebasedPlayerState?.(buildTTSStatePayload(state, locator));
}

function emitLocator(locator: Locator) {
  (window as any).updateTextLocator?.(JSON.stringify(locator));
}

export class WebTTSEngine {
  private readonly _nav: AnyNavigator;
  private readonly _publication: ReadiumPublication;
  private _prefs: WebTTSPreferences;

  private _iterator: PublicationContentIterator | null = null;
  private _currentElement: TextElement | null = null;
  private _lastBoundaryEmitTime = 0;
  private _destroyed = false;

  /** voice selected via setVoice() — overrides prefs.voice */
  private _selectedVoice: SpeechSynthesisVoice | null = null;
  /** per-language voice map: lang → voiceURI */
  private _langVoiceMap: Map<string, string> = new Map();

  constructor(
    nav: AnyNavigator,
    publication: ReadiumPublication,
    prefs: WebTTSPreferences
  ) {
    this._nav = nav;
    this._publication = publication;
    this._prefs = prefs;
  }

  // ---------------------------------------------------------------------------
  // Public API — mirrors the Dart TTS API contract
  // ---------------------------------------------------------------------------

  async play(fromLocator?: Locator): Promise<void> {
    if (this._destroyed) return;
    speechSynthesis.cancel();
    this._iterator = new PublicationContentIterator(
      this._publication,
      fromLocator,
      [
        (resource, locator) =>
          new HTMLResourceContentIterator(resource, locator),
      ]
    );
    await this._speakNext();
  }

  pause(): void {
    if (this._destroyed) return;
    speechSynthesis.pause();
    emitState("paused", this._currentElement?.locator ?? null);
  }

  resume(): void {
    if (this._destroyed) return;
    speechSynthesis.resume();
    emitState("playing", this._currentElement?.locator ?? null);
  }

  stop(): void {
    if (this._destroyed) return;
    speechSynthesis.cancel();
    this._iterator = null;
    this._currentElement = null;
    emitState("none", null);
  }

  async next(): Promise<void> {
    if (this._destroyed || !this._iterator) return;
    speechSynthesis.cancel();
    await this._speakNext();
  }

  async previous(): Promise<void> {
    if (this._destroyed || !this._iterator) return;
    speechSynthesis.cancel();
    await this._speakPrevious();
  }

  applyPreferences(prefs: WebTTSPreferences): void {
    this._prefs = prefs;
    // Changes take effect on the next utterance — current utterance continues unchanged.
  }

  setVoice(voiceURI: string, lang?: string): void {
    const voices = speechSynthesis.getVoices();
    const matched = voices.find((v) => v.voiceURI === voiceURI) ?? null;
    if (lang) {
      this._langVoiceMap.set(lang, voiceURI);
    } else {
      this._selectedVoice = matched;
    }
  }

  destroy(): void {
    this._destroyed = true;
    speechSynthesis.cancel();
    this._iterator = null;
    this._currentElement = null;
  }

  // ---------------------------------------------------------------------------
  // Voice list (static helper — no instance state needed)
  // ---------------------------------------------------------------------------

  static async getAvailableVoices(): Promise<string> {
    return serializeVoices();
  }

  // ---------------------------------------------------------------------------
  // Internal playback helpers
  // ---------------------------------------------------------------------------

  private async _speakNext(): Promise<void> {
    if (!this._iterator || this._destroyed) return;

    const hasNext = await this._iterator.hasNext();
    if (!hasNext) {
      emitState("ended", this._currentElement?.locator ?? null);
      return;
    }

    const element: ContentElement = this._iterator.next();
    if (!(element instanceof TextElement)) {
      // Skip non-text elements (images, audio, etc.) and advance.
      await this._speakNext();
      return;
    }

    this._currentElement = element;
    this._speakElement(element);
  }

  private async _speakPrevious(): Promise<void> {
    if (!this._iterator || this._destroyed) return;

    const hasPrev = await this._iterator.hasPrevious();
    if (!hasPrev) {
      // Already at start — replay current element if any.
      if (this._currentElement) {
        this._speakElement(this._currentElement);
      }
      return;
    }

    const element: ContentElement = this._iterator.previous();
    if (!(element instanceof TextElement)) {
      await this._speakPrevious();
      return;
    }

    this._currentElement = element;
    this._speakElement(element);
  }

  private _speakElement(element: TextElement): void {
    if (this._destroyed) return;

    const text = element.text;
    if (!text || text.trim().length === 0) {
      // Empty element — skip immediately.
      this._speakNext();
      return;
    }

    const utterance = new SpeechSynthesisUtterance(text);

    // Apply preferences.
    utterance.rate = this._prefs.rate;
    utterance.pitch = this._prefs.pitch;

    // Voice selection: per-language map → selected voice → prefs voice.
    const lang = this._resolveVoiceLang(element);
    const voice = lang
      ? (speechSynthesis.getVoices().find((v) => v.voiceURI === this._langVoiceMap.get(lang)) ?? this._selectedVoice ?? this._prefs.voice)
      : (this._selectedVoice ?? this._prefs.voice);
    if (voice) {
      utterance.voice = voice;
    } else if (this._prefs.lang) {
      utterance.lang = this._prefs.lang;
    }

    utterance.onstart = () => {
      if (this._destroyed) return;
      emitState("playing", element.locator);
      emitLocator(element.locator);
      // Scroll the visual navigator to the current paragraph.
      try {
        // Cross-resource transitions use animated=true; same-resource use false.
        this._nav.go(element.locator, false, () => {});
      } catch (_) {
        // Silently ignore navigation errors during TTS.
      }
    };

    utterance.onend = () => {
      if (this._destroyed) return;
      this._speakNext();
    };

    utterance.onerror = (ev) => {
      if (this._destroyed) return;
      // "interrupted" and "canceled" are expected when stop()/pause()/next() is called.
      if (ev.error === "interrupted" || ev.error === "canceled") return;
      console.warn("TTS error:", ev.error);
      emitState("failure", element.locator);
    };

    // onboundary: emit sub-utterance locators for word/sentence granularity.
    // Not available in all browsers — fails gracefully.
    utterance.onboundary = (ev) => {
      if (this._destroyed) return;
      if (ev.name !== "word" && ev.name !== "sentence") return;

      const now = Date.now();
      if (now - this._lastBoundaryEmitTime < BOUNDARY_THROTTLE_MS) return;
      this._lastBoundaryEmitTime = now;

      const segmentLocator = this._locatorForCharIndex(
        element,
        ev.charIndex,
        ev.charLength ?? 0
      );
      if (segmentLocator) {
        emitState("playing", segmentLocator);
        // NOTE: Do NOT call updateTextLocator here — sub-segment locators are
        // not stable enough for bookmark/position-save purposes.
      }
    };

    speechSynthesis.speak(utterance);
  }

  /**
   * Walks the element's TextSegments to find the one that contains the
   * character at `charIndex` (accumulated over the full text).
   */
  private _locatorForCharIndex(
    element: TextElement,
    charIndex: number,
    charLength: number
  ): Locator | null {
    if (!element.segments.length) return element.locator;

    let accumulated = 0;
    for (const seg of element.segments) {
      const start = accumulated;
      const end = accumulated + seg.text.length;
      if (charIndex >= start && charIndex < end) {
        return seg.locator;
      }
      // Include a space that speechSynthesis inserts between segments.
      accumulated = end + 1;
    }

    // charIndex is past the last segment — return the last segment locator.
    const last = element.segments[element.segments.length - 1];
    return last?.locator ?? element.locator;
  }

  /**
   * Best-effort language extraction for per-language voice selection.
   * The ts-toolkit exposes language as an attribute on the element.
   */
  private _resolveVoiceLang(element: TextElement): string | undefined {
    // Attributes are key-value pairs; language is conventionally stored as
    // an attribute with the key "language".
    const attrs = (element as any).attributes as Array<{ key: string; value: any }> | undefined;
    const langAttr = attrs?.find((a) => a.key === "language");
    return langAttr?.value ?? undefined;
  }
}
