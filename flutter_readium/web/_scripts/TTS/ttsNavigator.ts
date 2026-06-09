/**
 * WebTTSEngine — web TTS implementation using the browser's SpeechSynthesis API.
 *
 * Responsibilities:
 *  - Walk EPUB/WebPub text via PublicationContentIterator + HTMLResourceContentIterator.
 *  - Speak each TextElement via SpeechSynthesisUtterance.
 *  - Emit state payloads to window.updateTimebasedPlayerState (same contract as AudioNavigator).
 *  - Emit locator updates to window.updateTextLocator for position bookmarking.
 *  - Navigate the visual navigator to the current paragraph on each utterance start.
 *  - Apply utterance-level and word-level decorations via the onApplyDecorations callback
 *    when decoration styles are provided (set via setDecorationStyle on the Dart side).
 *
 * Known limitations:
 *  - onboundary sub-utterance granularity is not available in all browsers (Firefox, some
 *    mobile).  When absent, the engine falls back to utterance (paragraph) level silently.
 */

import { EpubNavigator, WebPubNavigator } from "@readium/navigator";
import {
  ContentElement,
  HTMLResourceContentIterator,
  Link,
  Locator,
  LocatorLocations,
  PublicationContentIterator,
  TextElement,
} from "@readium/shared";
import { ReadiumPublication } from "../extensions/ReadiumPublication";
import { createLogger } from "../logger";
import {
  WebTTSPreferences,
  serializeVoices,
} from "./ttsPreferences";

const log = createLogger("TTS");

/** Minimum ms between onboundary state emissions (throttle). */
const BOUNDARY_THROTTLE_MS = 100;
// How long to wait for `utterance.onstart` after calling `speak()` before
// considering the speechSynthesis engine wedged and triggering recovery.
const WEDGE_WATCHDOG_MS = 1500;

type AnyNavigator = EpubNavigator | WebPubNavigator;

/**
 * Collapses any run of whitespace to a single space and trims.
 * The upstream HTMLResourceContentIterator preserves source-XHTML whitespace
 * (indentation, line breaks) verbatim in LocatorText, which clutters logs and
 * persisted bookmarks without adding information.
 */
function normalizeWhitespace(s: string | undefined | null): string | undefined {
  if (!s) return undefined;
  const trimmed = s.replace(/\s+/g, " ").trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

/** Returns a JSON-cloned locator with LocatorText fields whitespace-normalized. */
function normalizeLocatorJson(locator: Locator): any {
  // Use serialize() so otherLocations Map entries survive the JSON round-trip.
  const clone = JSON.parse(JSON.stringify(locator.serialize()));
  if (clone?.text) {
    clone.text = {
      before: normalizeWhitespace(clone.text.before),
      highlight: normalizeWhitespace(clone.text.highlight),
      after: normalizeWhitespace(clone.text.after),
    };
  }
  return clone;
}

/** JSON payload shape matching ReadiumTimebasedState. */
function buildTTSStatePayload(
  state: string,
  locator: Locator | null
): string {
  return JSON.stringify({
    state,
    currentOffset: null,
    currentDuration: null,
    currentLocator: locator ? normalizeLocatorJson(locator) : null,
  });
}

function emitState(state: string, locator: Locator | null) {
  window.updateTimebasedPlayerState?.(buildTTSStatePayload(state, locator));
}

function emitLocator(locator: Locator) {
  window.updateTextLocator?.(JSON.stringify(normalizeLocatorJson(locator)));
}

// ---------------------------------------------------------------------------
// TOC-href enrichment (mirrors the equivalent helpers in epubNavigator.ts)
// ---------------------------------------------------------------------------

/**
 * Recursively walks the publication's TOC link tree and returns a flat list.
 * Duplicated from epubNavigator.ts to avoid a cross-module import that would
 * touch a file the downstream refactor branch is already restructuring.
 */
function flattenToc(items: Link[]): Link[] {
  const out: Link[] = [];
  for (const link of items) {
    out.push(link);
    const children = link.children?.items;
    if (children && children.length > 0) {
      out.push(...flattenToc(children));
    }
  }
  return out;
}

/**
 * Returns a copy of `locator` with `tocHref` set in `locations.otherLocations`,
 * matching the current chapter's TOC href by resource href (fragment-stripped).
 * No-op when `flatToc` is empty, no match is found, or `tocHref` is already set.
 */
function enrichWithTocHref(locator: Locator, flatToc: Link[]): Locator {
  if (flatToc.length === 0) return locator;
  const tocHref = _findCurrentTocHref(locator.href, flatToc);
  if (!tocHref) return locator;
  const existing = locator.locations?.otherLocations ?? new Map<string, any>();
  // Avoid clobbering an existing tocHref (e.g. set by an upstream caller).
  if (existing.get("tocHref") === tocHref) return locator;
  const merged = new Map(existing);
  merged.set("tocHref", tocHref);
  return new Locator({
    href: locator.href,
    type: locator.type,
    title: locator.title,
    text: locator.text,
    locations: new LocatorLocations({
      fragments: locator.locations?.fragments,
      progression: locator.locations?.progression,
      position: locator.locations?.position,
      totalProgression: locator.locations?.totalProgression,
      otherLocations: merged,
    }),
  });
}

function _findCurrentTocHref(
  resourceHref: string,
  flatToc: Link[]
): string | undefined {
  const targetPath = _stripFragment(resourceHref);
  const match = flatToc.find((l) => _stripFragment(l.href) === targetPath);
  return match?.href;
}

function _stripFragment(href: string): string {
  const i = href.indexOf("#");
  return i === -1 ? href : href.substring(0, i);
}

export class WebTTSEngine {
  private readonly _nav: AnyNavigator;
  private readonly _publication: ReadiumPublication;
  private _prefs: WebTTSPreferences;
  /**
   * When true (default), each utterance scrolls the visual navigator to the
   * spoken paragraph. Mirrors `EPUBPreferences.disableSynchronization` on native
   * — see kotlin-toolkit's gate at ReadiumReader.kt:1420 for the equivalent
   * behaviour on Android.
   */
  private _syncEnabled: boolean;

  private _iterator: PublicationContentIterator | null = null;
  private _currentElement: TextElement | null = null;
  private _lastBoundaryEmitTime = 0;
  private _destroyed = false;

  /** voice selected via setVoice() — overrides prefs.voice */
  private _selectedVoice: SpeechSynthesisVoice | null = null;
  /** per-language voice map: lang -> voiceURI */
  private _langVoiceMap: Map<string, string> = new Map();

  /**
   * Flattened TOC built once per session. Used to enrich every Dart-facing
   * locator emission with `tocHref` so chapter-aware features (next/previous
   * chapter, current-chapter display) work during TTS playback — matching the
   * behaviour already present for visual navigation and audiobook playback.
   */
  private readonly _flatToc: Link[];

  /** Decoration style for the active utterance span (null = no utterance decoration). */
  private _utteranceStyle: object | null;
  /** Decoration style for the active word/boundary span (null = no range decoration). */
  private _rangeStyle: object | null;
  /**
   * Callback invoked to apply a decoration group. Receives the group name and a
   * JSON-encoded array of ReaderDecoration objects (same shape as the Dart
   * applyDecorations contract). Passing an empty array clears the group.
   */
  private _onApplyDecorations: ((group: string, decorationsJson: string) => void) | null;

  constructor(
    nav: AnyNavigator,
    publication: ReadiumPublication,
    prefs: WebTTSPreferences,
    syncEnabled: boolean = true,
    utteranceStyle: object | null = null,
    rangeStyle: object | null = null,
    onApplyDecorations: ((group: string, decorationsJson: string) => void) | null = null
  ) {
    this._nav = nav;
    this._publication = publication;
    this._prefs = prefs;
    this._syncEnabled = syncEnabled;
    this._utteranceStyle = utteranceStyle;
    this._rangeStyle = rangeStyle;
    this._onApplyDecorations = onApplyDecorations;
    this._flatToc = flattenToc(publication.manifest.toc?.items ?? []);
    // Hard-reset Chrome's speechSynthesis on construction. Leftover state from
    // a previous publication (or a wedge that survived a page navigation) can
    // prevent the very first speak() of the new session from dispatching
    // onstart. Calling cancel() on an idle engine is a no-op.
    try {
      speechSynthesis.cancel();
    } catch {
      /* ignore — unsupported environment */
    }
  }

  /**
   * Toggles visual-navigator synchronization on the fly. Called when the Flutter
   * side updates `EPUBPreferences.disableSynchronization` during an active TTS
   * session — see ReadiumReader.setEPUBPreferences.
   */
  setSyncEnabled(enabled: boolean): void {
    this._syncEnabled = enabled;
  }

  /**
   * Updates the decoration styles for utterance and range highlighting.
   * Takes effect on the next utterance; current utterance is not re-decorated.
   */
  updateDecorationStyles(utteranceStyle: object | null, rangeStyle: object | null): void {
    this._utteranceStyle = utteranceStyle;
    this._rangeStyle = rangeStyle;
  }

  // ---------------------------------------------------------------------------
  // Public API — mirrors the Dart TTS API contract
  // ---------------------------------------------------------------------------

  async play(fromLocator?: Locator): Promise<void> {
    if (this._destroyed) return;
    log.info("play", fromLocator ? "(from locator)" : "", {
      speaking: speechSynthesis.speaking,
      pending: speechSynthesis.pending,
      paused: speechSynthesis.paused,
      voices: speechSynthesis.getVoices().length,
    });
    this._clearDecorations();
    // Prime the engine synchronously inside the user-gesture frame.
    // Chromium silently swallows the first async speak() if the gesture has
    // already expired by the time we call it (after awaiting hasNext()).
    // A zero-length utterance consumes the gesture and wakes the engine.
    log.debug("Priming speechSynthesis engine");
    speechSynthesis.speak(new SpeechSynthesisUtterance(""));
    // Only cancel if there's something queued — cancel() on an idle engine
    // can leave Chromium in a stalled state.
    const wasActive = speechSynthesis.speaking || speechSynthesis.pending;
    if (wasActive) {
      speechSynthesis.cancel();
    }
    this._iterator = new PublicationContentIterator(
      this._publication,
      fromLocator,
      [
        (resource, locator) =>
          new HTMLResourceContentIterator(resource, locator),
      ]
    );
    // Give Chromium's TTS state machine a tick to settle after cancel().
    // Without this, a subsequent speak() can flip `speaking: true` and never
    // dispatch utterance.onstart — the classic wedge that strikes when play()
    // is invoked twice in quick succession (e.g. ttsEnable followed by an
    // immediate play(locator) from the Dart side).
    if (wasActive) {
      await new Promise<void>((resolve) => setTimeout(resolve, 50));
      if (this._destroyed) return;
    }
    log.debug("Initialized - Speaking first element");
    await this._speakNext();
  }

  pause(): void {
    if (this._destroyed) return;
    log.debug("pause");
    speechSynthesis.pause();
    emitState("paused", this._currentElement?.locator ?? null);
  }

  resume(): void {
    if (this._destroyed) return;
    log.debug("resume");
    speechSynthesis.resume();
    emitState("playing", this._currentElement?.locator ?? null);
  }

  stop(): void {
    if (this._destroyed) return;
    log.info("stop");
    speechSynthesis.cancel();
    this._iterator = null;
    this._currentElement = null;
    this._clearDecorations();
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
    if (!matched && !lang) {
      log.warn("Voice not found:", voiceURI);
    } else {
      log.debug("Voice set:", voiceURI, lang ? `(lang: ${lang})` : "");
    }
    if (lang) {
      this._langVoiceMap.set(lang, voiceURI);
    } else {
      this._selectedVoice = matched;
    }
  }

  destroy(): void {
    log.info("destroy");
    this._destroyed = true;
    speechSynthesis.cancel();
    this._iterator = null;
    this._currentElement = null;
    this._clearDecorations();
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

    log.debug("_speakNext: awaiting hasNext");
    const hasNext = await this._iterator.hasNext();
    log.debug("_speakNext: hasNext =", hasNext);
    if (!hasNext) {
      log.info("TTS reached end of publication");
      emitState("ended", this._currentElement?.locator ?? null);
      return;
    }

    const element: ContentElement = this._iterator.next();
    log.debug("_speakNext: next element", {
      kind: element.constructor.name,
      isText: element instanceof TextElement,
    });
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
    log.debug("_speakElement", {
      textLen: text?.length ?? 0,
      textPreview: text?.slice(0, 60),
    });
    if (!text || text.trim().length === 0) {
      log.debug("_speakElement: empty text, skipping");
      this._speakNext();
      return;
    }

    const utterance = new SpeechSynthesisUtterance(text);

    // Apply preferences.
    utterance.rate = this._prefs.rate;
    utterance.pitch = this._prefs.pitch;

    // Voice selection: per-language map -> selected voice -> prefs voice.
    const lang = this._resolveVoiceLang(element);
    const voice = lang
      ? (speechSynthesis.getVoices().find((v) => v.voiceURI === this._langVoiceMap.get(lang)) ?? this._selectedVoice ?? this._prefs.voice)
      : (this._selectedVoice ?? this._prefs.voice);
    if (voice) {
      utterance.voice = voice;
    } else if (this._prefs.lang) {
      utterance.lang = this._prefs.lang;
    }
    log.debug("_speakElement: utterance config", {
      voice: voice?.name ?? "(default)",
      lang: utterance.lang || "(none)",
      rate: utterance.rate,
      pitch: utterance.pitch,
      elementLang: lang ?? "(none)",
    });

    // Wedge detector — Chrome occasionally flips `speaking: true` on `speak()`
    // without ever dispatching `onstart` (a known speechSynthesis bug,
    // especially after page navigation). If `onstart` hasn't fired within the
    // watchdog timeout AND the engine claims to be speaking, do one hard reset
    // and re-speak the same utterance. A single retry — if recovery also
    // wedges, surface a failure instead of looping forever.
    let started = false;
    let recovered = false;
    let watchdog: ReturnType<typeof setTimeout> | null = null;
    const clearWatchdog = () => {
      if (watchdog !== null) {
        clearTimeout(watchdog);
        watchdog = null;
      }
    };
    const armWatchdog = () => {
      watchdog = setTimeout(() => {
        watchdog = null;
        if (started || this._destroyed) return;
        if (!speechSynthesis.speaking) return; // engine moved on; nothing to recover
        if (recovered) {
          log.warn("speechSynthesis wedge persisted after recovery — aborting utterance");
          emitState("failure", element.locator);
          return;
        }
        recovered = true;
        log.warn("speechSynthesis wedge detected — attempting recovery");
        try { speechSynthesis.cancel(); } catch { /* ignore */ }
        setTimeout(() => {
          if (this._destroyed || started) return;
          try {
            // Prime, then re-speak. Re-using the utterance is supported —
            // its event handlers fire for each speak() cycle.
            speechSynthesis.speak(new SpeechSynthesisUtterance(""));
            speechSynthesis.speak(utterance);
            armWatchdog();
          } catch (e) {
            log.warn("speechSynthesis recovery failed:", e);
            emitState("failure", element.locator);
          }
        }, 200);
      }, WEDGE_WATCHDOG_MS);
    };

    utterance.onstart = () => {
      log.debug("utterance.onstart");
      started = true;
      clearWatchdog();
      if (this._destroyed) return;
      // Enrich with tocHref so chapter-aware Dart consumers (next/previous chapter,
      // current-chapter display) work during TTS playback. Decoration calls keep the
      // raw locator — they're href/cssSelector-based and don't need tocHref.
      const enrichedLocator = enrichWithTocHref(element.locator, this._flatToc);
      emitState("playing", enrichedLocator);
      emitLocator(enrichedLocator);
      // Apply utterance-level decoration; always clear any stale range from the previous utterance.
      this._applyDecoration("tts_utterance", element.locator, this._utteranceStyle);
      this._onApplyDecorations?.("tts_range", "[]");
      // Scroll the visual navigator to the current paragraph, unless the user
      // has opted out via EPUBPreferences.disableSynchronization.
      if (this._syncEnabled) {
        try {
          // Cross-resource transitions use animated=true; same-resource use false.
          this._nav.go(element.locator, false, () => {});
        } catch (navError) {
            log.warn("TTS navigator sync failed:", navError);
          }
      }
    };

    utterance.onend = () => {
      log.debug("utterance.onend");
      clearWatchdog();
      if (this._destroyed) return;
      this._speakNext();
    };

    utterance.onerror = (ev) => {
      // Recovery-induced cancel fires onerror with "canceled" on the original
      // attempt — keep the watchdog alive so the retry is still monitored.
      if (!recovered) clearWatchdog();
      if (this._destroyed) return;
      // "interrupted" and "canceled" are expected when stop()/pause()/next() is called.
      if (ev.error === "interrupted" || ev.error === "canceled") {
        log.debug("utterance.onerror (expected):", ev.error);
        return;
      }
      log.warn("utterance.onerror", ev.error);
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
        emitState("playing", enrichWithTocHref(segmentLocator, this._flatToc));
        // NOTE: Do NOT call updateTextLocator here — sub-segment locators are
        // not stable enough for bookmark/position-save purposes.
        // Skip the range decoration when the segment spans exactly the same
        // text as the utterance — otherwise the range highlight stacks on top
        // of the utterance highlight, double-decorating the whole paragraph.
        if (!this._locatorHighlightsSameText(segmentLocator, element.locator)) {
          this._applyDecoration("tts_range", segmentLocator, this._rangeStyle);
        }
      }
    };

    log.debug("_speakElement: calling speechSynthesis.speak");
    speechSynthesis.speak(utterance);
    log.debug("_speakElement: after speak()", {
      speaking: speechSynthesis.speaking,
      pending: speechSynthesis.pending,
      paused: speechSynthesis.paused,
    });
    armWatchdog();
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
   * True when both locators highlight the same text — i.e. the boundary
   * segment spans exactly the utterance. Comparing `text.highlight` is enough:
   * if the spoken text matches, the range decoration would just stack on the
   * utterance decoration over the same span.
   */
  private _locatorHighlightsSameText(a: Locator, b: Locator): boolean {
    return normalizeWhitespace(a.text?.highlight) === normalizeWhitespace(b.text?.highlight);
  }

  private _resolveVoiceLang(element: TextElement): string | undefined {
    // `language` getter comes from AttributesHolder (TextElement's grandparent in @readium/shared).
    // Cast is needed because the package's exported types don't surface the inherited getter.
    const elementLang = (element as any).language as string | undefined;
    if (elementLang) return elementLang;
    // Fall back to the publication's primary language. EPUBs commonly declare
    // `lang` only on `<html>`, which upstream's AttributesHolder does not see,
    // so without this fallback `utterance.lang` stays unset and Chrome routes
    // the text to its default UI-language voice — which silently wedges
    // speechSynthesis on short non-English utterances after a `cancel()`.
    return this._publication.metadata.languages?.[0];
  }

  /** Clear both TTS decoration groups. No-op when no callback is registered. */
  private _clearDecorations(): void {
    if (!this._onApplyDecorations) return;
    this._onApplyDecorations("tts_utterance", "[]");
    this._onApplyDecorations("tts_range", "[]");
  }

  /**
   * Apply a single-decoration group. Skips silently when the callback, locator,
   * or style is absent. Errors are swallowed so decoration failures never abort
   * speech playback.
   */
  private _applyDecoration(group: string, locator: Locator | null, style: object | null): void {
    if (!this._onApplyDecorations || !locator || !style) return;
    try {
      const decoration = [{ id: locator.href, locator: locator.serialize(), style }];
      this._onApplyDecorations(group, JSON.stringify(decoration));
    } catch (e) {
      log.warn("TTS: failed to apply decoration:", e);
    }
  }
}
